// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:netcrux/services/remote/cxp/netcrux_name_resolver.dart';

/// Who NetCrux is on CXP: its wire name, its default port and preference-key
/// prefix, the element kinds it can highlight when a peer asks, and the
/// receiver-side rule every peer-supplied path is checked against.
///
/// Everything else about the CXP lifecycle (starting and stopping the server,
/// discovery, the peer list, settings, acknowledgements) is the shared
/// runtime's.
///
/// The containment is the binding's default, the floor
/// (`kCxpOpenArtifactContainment`), not the directories the user has opened.
/// The shared server holds one rule for both requests it screens, and a rooted
/// one strips the path hint from a `request_open_artifact` for a design NetCrux
/// has never opened, which is the very request that route exists to honour. A
/// `request_open_source` keeps its roots: the request handler applies the
/// rooted rule to the path it is about to hand an editor.
const CruxCxpProductBinding kNetcruxCxpBinding = CruxCxpProductBinding(
  productName: 'netcrux',
  defaultPort: 54323,
  prefsPrefix: 'netcrux.',
  acceptedKinds: <ElementKind>[
    ElementKind.net,
    ElementKind.port,
    ElementKind.instance,
    ElementKind.signal,
    ElementKind.scope,
    ElementKind.source,
  ],
  nameResolver: NetcruxNameResolver(),
);
