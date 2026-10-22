
use std::collections::VecDeque;

use indexmap::IndexMap;

use crate::alg_layered::graph::{LGraphArena, LGraphId, LNodeId};
use crate::alg_layered::options_gen as lopts;
use crate::alg_layered::options_gen::EdgeStraighteningStrategy;
use crate::alg_layered::spacings;

use super::bk_aligned_layout::{BKAlignedLayout, HDirection, VDirection};
use super::neighborhood_information::{nid, NeighborhoodInformation};
use super::threshold_strategy::ThresholdStrategy;

/// A node of the class graph. Referenced by index into
/// `BKCompactor::class_nodes`.
struct ClassNode {
    class_shift: Option<f64>,
    node: LNodeId,
    outgoing: Vec<ClassEdge>,
    indegree: i32,
}

/// An edge of the class graph; holds the required separation between the
/// connected classes.
#[derive(Clone, Copy)]
struct ClassEdge {
    separation: f64,
    target: usize,
}

/// One block's walk in `BKCompactor::place_block`: the locals of Java's
/// recursive `placeBlock`, kept on an explicit stack.
struct PlaceBlockFrame {
    root: LNodeId,
    current_node: LNodeId,
    thresh: f64,
    is_initial_assignment: bool,
    /// The neighbour and its block's root, while the walk waits for that
    /// block to be placed.
    pending: Option<(LNodeId, LNodeId)>,
}

pub struct BKCompactor {
    /// Specific threshold strategy to be used for execution.
    thresh_strategy: ThresholdStrategy,
    /// Representation of the class graph; an insertion-ordered map is used
    /// here for determinism, see `place_classes` for why this cannot change
    /// the outcome.
    sink_nodes: IndexMap<LNodeId, usize>,
    class_nodes: Vec<ClassNode>,
}

impl BKCompactor {
    pub fn new(a: &LGraphArena, graph: LGraphId) -> Self {
        // configure the requested threshold strategy
        let straightening: EdgeStraighteningStrategy = a
            .graph(graph)
            .properties
            .get(&lopts::NODE_PLACEMENT_BK_EDGE_STRAIGHTENING);
        BKCompactor {
            thresh_strategy: ThresholdStrategy::new(
                straightening == EdgeStraighteningStrategy::IMPROVE_STRAIGHTNESS,
            ),
            sink_nodes: IndexMap::new(),
            class_nodes: Vec::new(),
        }
    }

    /// In this step, actual coordinates are calculated for blocks and its
    /// nodes. First, all blocks are placed, trying to avoid any crossing of
    /// the blocks. Then, the blocks are shifted towards each other if there
    /// is any space for compaction.
    pub fn horizontal_compaction(
        &mut self,
        a: &LGraphArena,
        graph: LGraphId,
        ni: &NeighborhoodInformation,
        bal: &mut BKAlignedLayout,
    ) {
        // Initialize fields with basic values, partially depending on the direction
        for &layer in &a.graph(graph).layers {
            for &node in &a.layer(layer).nodes {
                let i = nid(a, node);
                bal.sink[i] = Some(node);
                bal.shift[i] = Some(if bal.vdir == Some(VDirection::Up) {
                    f64::NEG_INFINITY
                } else {
                    f64::INFINITY
                });
            }
        }
        // clear any previous sinks
        self.sink_nodes.clear();
        self.class_nodes.clear();

        // If the horizontal direction is LEFT, the layers are traversed from
        // right to left, thus a reverse iterator is needed (note that this
        // does not change the original list of layers)
        let mut layers = a.graph(graph).layers.clone();
        if bal.hdir == Some(HDirection::Left) {
            layers.reverse();
        }

        // init threshold strategy
        self.thresh_strategy.init();
        // mark all blocks as unplaced
        for y in bal.y.iter_mut() {
            *y = None;
        }

        for &layer in &layers {
            // As with layers, we need a reversed iterator for blocks for
            // different directions
            let mut nodes = a.layer(layer).nodes.clone();
            if bal.vdir == Some(VDirection::Up) {
                nodes.reverse();
            }

            // Do an initial placement for all blocks
            for v in nodes {
                if bal.root[nid(a, v)] == Some(v) {
                    self.place_block(a, graph, ni, bal, v);
                }
            }
        }

        // Try to compact classes by shifting them towards each other if there
        // is space between them. Other than the original algorithm we use a
        // "class graph" here in conjunction with a longest path layering
        // based on previously calculated separations between any pair of
        // adjacent classes. This allows to have different node sizes and
        // disconnected graphs.
        self.place_classes(a, bal);

        // apply final coordinates
        for &layer in &layers {
            let nodes = a.layer(layer).nodes.clone();
            for v in nodes {
                let i = nid(a, v);
                bal.y[i] = bal.y[nid(a, bal.root[i].unwrap())];

                // If this is the root node of the block, check if the whole
                // block can be shifted to further compact the drawing (the
                // block's non-root nodes will be processed later by this loop
                // and will thus use the updated y position calculated here)
                if bal.root[i] == Some(v) {
                    let sink_shift = bal.shift[nid(a, bal.sink[i].unwrap())].unwrap();

                    if (bal.vdir == Some(VDirection::Up) && sink_shift > f64::NEG_INFINITY)
                        || (bal.vdir == Some(VDirection::Down) && sink_shift < f64::INFINITY)
                    {
                        bal.y[i] = Some(bal.y[i].unwrap() + sink_shift);
                    }
                }
            }
        }

        // all blocks were placed, shift latecomers
        self.thresh_strategy.post_process(a, ni, bal);
    }

    /// Blocks are placed based on their root node. This is done by going
    /// through all layers the block occupies and moving the whole block
    /// upwards / downwards if there are blocks that it overlaps with.
    ///
    /// Java places the neighbouring block by recursing from inside the walk
    /// along this block, once per block in the chain, which overflows a small
    /// stack on a large graph. This keeps the walks on an explicit stack of
    /// [`PlaceBlockFrame`]s instead: a frame that needs its neighbour placed
    /// first is suspended, the neighbour's frame runs to completion, and the
    /// suspended frame resumes where the recursive call returned. Every step
    /// happens in the recursive version's order, so the result is the same.
    fn place_block(
        &mut self,
        a: &LGraphArena,
        graph: LGraphId,
        ni: &NeighborhoodInformation,
        bal: &mut BKAlignedLayout,
        root: LNodeId,
    ) {
        // Skip if the block was already placed
        if bal.y[nid(a, root)].is_some() {
            return;
        }
        let mut stack = vec![Self::begin_block(a, bal, root)];
        while let Some(mut frame) = stack.pop() {
            if let Some(neighbor_root) = self.walk_block(a, graph, ni, bal, &mut frame) {
                stack.push(frame);
                stack.push(Self::begin_block(a, bal, neighbor_root));
            }
        }
    }

    /// Marks the unplaced block `root` as placed at 0.0 (the initial
    /// placement) and returns the frame that walks it.
    fn begin_block(a: &LGraphArena, bal: &mut BKAlignedLayout, root: LNodeId) -> PlaceBlockFrame {
        // Initial placement
        // As opposed to the original algorithm we cannot rely on the fact
        // that 0.0 as initial block position is always feasible (KIPRA-1426).
        bal.y[nid(a, root)] = Some(0.0);
        PlaceBlockFrame {
            root,
            current_node: root,
            thresh: if bal.vdir == Some(VDirection::Down) {
                f64::NEG_INFINITY
            } else {
                f64::INFINITY
            },
            is_initial_assignment: true,
            pending: None,
        }
    }

    /// Walks the block of `frame.root` from `frame.current_node`. Returns the
    /// root of a neighbouring block that must be placed before the walk can
    /// go on, with the walk suspended in `frame.pending`; returns `None` when
    /// the block is placed.
    fn walk_block(
        &mut self,
        a: &LGraphArena,
        graph: LGraphId,
        ni: &NeighborhoodInformation,
        bal: &mut BKAlignedLayout,
        frame: &mut PlaceBlockFrame,
    ) -> Option<LNodeId> {
        let root = frame.root;
        // Iterate through block and determine, where the block can be placed
        // (until we arrive at the block's root node again)
        loop {
            let current_node = frame.current_node;
            let neighbor_and_root = match frame.pending.take() {
                // Resumed: the neighbouring block has just been placed.
                Some(pending) => Some(pending),
                None => {
                    let current_index_in_layer = ni.node_index[nid(a, current_node)];
                    let current_layer = a.node(current_node).layer.unwrap();
                    let current_layer_size = a.layer(current_layer).nodes.len() as i32;

                    // If the node is the top or bottom node of its layer, it
                    // can be placed safely since it is the first to be placed
                    // in its layer. If it's not, we'll have to check its
                    // neighbours
                    if (bal.vdir == Some(VDirection::Down) && current_index_in_layer > 0)
                        || (bal.vdir == Some(VDirection::Up)
                            && current_index_in_layer < current_layer_size - 1)
                    {
                        // Get the node which is above / below the current
                        // node as well as the root of its block
                        let neighbor = if bal.vdir == Some(VDirection::Up) {
                            a.layer(current_layer).nodes[(current_index_in_layer + 1) as usize]
                        } else {
                            a.layer(current_layer).nodes[(current_index_in_layer - 1) as usize]
                        };
                        let neighbor_root = bal.root[nid(a, neighbor)].unwrap();

                        // Ensure the neighbor was already placed
                        if bal.y[nid(a, neighbor_root)].is_none() {
                            frame.pending = Some((neighbor, neighbor_root));
                            return Some(neighbor_root);
                        }
                        Some((neighbor, neighbor_root))
                    } else {
                        None
                    }
                }
            };

            if let Some((neighbor, neighbor_root)) = neighbor_and_root {
                // calculate threshold value for additional straight edges;
                // this call has to be _after_ place block, otherwise the
                // order of the elements in the postprocessing queue is wrong
                frame.thresh = self.thresh_strategy.calculate_threshold(
                    a,
                    bal,
                    frame.thresh,
                    root,
                    current_node,
                );

                // Note that the two nodes and their blocks form a unit called
                // class in the original algorithm. These are combinations of
                // blocks which play a role in the final compaction
                if bal.sink[nid(a, root)] == Some(root) {
                    bal.sink[nid(a, root)] = bal.sink[nid(a, neighbor_root)];
                }

                // Check if the blocks of the two nodes are members of the same class
                if bal.sink[nid(a, root)] == bal.sink[nid(a, neighbor_root)] {
                    // They are part of the same class

                    // The minimal spacing between the two nodes depends on
                    // their node type
                    let spacing = spacings::vertical_spacing(a, current_node, neighbor);
                    let thresh = frame.thresh;

                    // Determine the block's final position
                    if bal.vdir == Some(VDirection::Up) {
                        let current_block_position = bal.y[nid(a, root)].unwrap();
                        let new_position = bal.y[nid(a, neighbor_root)].unwrap()
                            + bal.inner_shift[nid(a, neighbor)].unwrap()
                            - a.node(neighbor).margin.top
                            - spacing
                            - a.node(current_node).margin.bottom
                            - a.node(current_node).size.y
                            - bal.inner_shift[nid(a, current_node)].unwrap();

                        bal.y[nid(a, root)] = Some(if frame.is_initial_assignment {
                            frame.is_initial_assignment = false;
                            f64::min(new_position, thresh)
                        } else {
                            f64::min(current_block_position, f64::min(new_position, thresh))
                        });
                    } else {
                        // DOWN
                        let current_block_position = bal.y[nid(a, root)].unwrap();
                        let new_position = bal.y[nid(a, neighbor_root)].unwrap()
                            + bal.inner_shift[nid(a, neighbor)].unwrap()
                            + a.node(neighbor).size.y
                            + a.node(neighbor).margin.bottom
                            + spacing
                            + a.node(current_node).margin.top
                            - bal.inner_shift[nid(a, current_node)].unwrap();

                        bal.y[nid(a, root)] = Some(if frame.is_initial_assignment {
                            frame.is_initial_assignment = false;
                            f64::max(new_position, thresh)
                        } else {
                            f64::max(current_block_position, f64::max(new_position, thresh))
                        });
                    }
                } else {
                    // CLASSES

                    // They are not part of the same class. Compute how the
                    // two classes can be compacted later. Hence we determine
                    // a minimal required space between the two classes
                    // relative to the two class sinks.
                    let spacing: f64 = a.graph(graph).properties.get(&lopts::SPACING_NODE_NODE);

                    let sink_node = self.get_or_create_class_node(bal.sink[nid(a, root)].unwrap());
                    let neighbor_sink =
                        self.get_or_create_class_node(bal.sink[nid(a, neighbor_root)].unwrap());

                    if bal.vdir == Some(VDirection::Up) {
                        //  possible setup:
                        //  root         --> currentNode
                        //  neighborRoot --> neighbor
                        let required_space = bal.y[nid(a, root)].unwrap()
                            + bal.inner_shift[nid(a, current_node)].unwrap()
                            + a.node(current_node).size.y
                            + a.node(current_node).margin.bottom
                            + spacing
                            - (bal.y[nid(a, neighbor_root)].unwrap()
                                + bal.inner_shift[nid(a, neighbor)].unwrap()
                                - a.node(neighbor).margin.top);

                        // add an edge to the class graph
                        self.add_class_edge(sink_node, neighbor_sink, required_space);
                    } else {
                        // DOWN
                        //  possible setup:
                        //  neighborRoot --> neighbor
                        //  root         --> currentNode
                        let required_space = bal.y[nid(a, root)].unwrap()
                            + bal.inner_shift[nid(a, current_node)].unwrap()
                            - a.node(current_node).margin.top
                            - bal.y[nid(a, neighbor_root)].unwrap()
                            - bal.inner_shift[nid(a, neighbor)].unwrap()
                            - a.node(neighbor).size.y
                            - a.node(neighbor).margin.bottom
                            - spacing;

                        // add an edge to the class graph
                        self.add_class_edge(sink_node, neighbor_sink, required_space);
                    }
                }
            } else {
                frame.thresh = self.thresh_strategy.calculate_threshold(
                    a,
                    bal,
                    frame.thresh,
                    root,
                    current_node,
                );
            }

            // Get the next node in the block
            frame.current_node = bal.align[nid(a, current_node)].unwrap();
            if frame.current_node == root {
                break;
            }
        }

        self.thresh_strategy.finish_block(root);
        None
    }

    /// Propagates shifts through the
    /// class graph in a longest path layering fashion.
    ///
    /// The queue is seeded from the class node values, which have no defined
    /// order; since every class node is dequeued only after all of its
    /// predecessors have been fully processed and min/max are
    /// order-insensitive, the resulting shifts are independent of that order.
    fn place_classes(&mut self, a: &LGraphArena, bal: &mut BKAlignedLayout) {
        // collect sinks of the class graph
        let mut sinks: VecDeque<usize> = VecDeque::new();
        for &n in self.sink_nodes.values() {
            if self.class_nodes[n].indegree == 0 {
                sinks.push_back(n);
            }
        }

        // propagate shifts in a longest path layering fashion
        while let Some(n) = sinks.pop_front() {
            // position the root of the class node tree
            if self.class_nodes[n].class_shift.is_none() {
                self.class_nodes[n].class_shift = Some(0.0);
            }
            let n_shift = self.class_nodes[n].class_shift.unwrap();

            for i in 0..self.class_nodes[n].outgoing.len() {
                let e = self.class_nodes[n].outgoing[i];
                let target = &mut self.class_nodes[e.target];

                // initial position of a target does not depend on previous
                // positions (we need this as we cannot assume the top-most
                // position to be 0)
                target.class_shift = Some(match target.class_shift {
                    None => n_shift + e.separation,
                    Some(current) => {
                        if bal.vdir == Some(VDirection::Down) {
                            f64::min(current, n_shift + e.separation)
                        } else {
                            f64::max(current, n_shift + e.separation)
                        }
                    }
                });

                target.indegree -= 1;

                if target.indegree == 0 {
                    sinks.push_back(e.target);
                }
            }
        }

        // remember final shifts for all classes such that they can be applied
        // as absolute coordinates
        for &n in self.sink_nodes.values() {
            let cn = &self.class_nodes[n];
            bal.shift[nid(a, cn.node)] = cn.class_shift;
        }
    }

    fn get_or_create_class_node(&mut self, sink_node: LNodeId) -> usize {
        if let Some(&idx) = self.sink_nodes.get(&sink_node) {
            return idx;
        }
        let idx = self.class_nodes.len();
        self.class_nodes.push(ClassNode {
            class_shift: None,
            node: sink_node,
            outgoing: Vec::new(),
            indegree: 0,
        });
        self.sink_nodes.insert(sink_node, idx);
        idx
    }

    fn add_class_edge(&mut self, source: usize, target: usize, separation: f64) {
        self.class_nodes[target].indegree += 1;
        self.class_nodes[source].outgoing.push(ClassEdge { separation, target });
    }
}
