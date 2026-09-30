# Make a custom symbol

Your design instantiates the same arbiter twenty times, and every one renders as an identical gray box. This recipe gives that module a custom symbol so it reads at a glance wherever it appears — and parks the symbol in your user library so the next project gets it for free.

| | |
|---|---|
| **Goal** | Draw a custom symbol for a reusable module and reuse it across projects. |
| **Time** | About 12 minutes |
| **Tier** | <span class="tier tier-pro">Pro</span> — custom cell symbols. |
| **You will use** | The [symbol manager](customizing.md#symbol-manager) and the [three-tab symbol editor](customizing.md#create). |

## Before you start {#before}

Know the module's exact module type name and its port list — names, and which side each port belongs on. Having an SVG sketch ready helps, but you can also start from scratch.

## Steps {#steps}

1. **Open the editor.**

    The quickest way is to right-click an instance of the module on the canvas and choose **Create Symbol for This Module**, which fills in its module type for you. Or open `Tools → Open Custom Cell Symbol Manager…`.

2. **Create the symbol.**

    In the manager, click **New Symbol** to start fresh, or **Import from SVG…** to load a drawing as the starting point.

3. **Draw it on the SVG Content tab.**

    On the **SVG Content** tab, edit the markup and watch the live preview update. On import and save, the [SVG sanitizer](customizing.md#sanitizer) strips any scripts, event handlers, external references and `javascript:` URLs — the symbol is artwork only.

4. **Place the port anchors.**

    On the **Port Anchors** tab, **Add port** for each port, pick its side, and set its position with the slider so wires meet the shape at the right point, not the bounding box.

5. **Set the metadata and scope.**

    On the **Metadata** tab, confirm the **Module type** and add an **Author** and **Notes**. Set **Storage scope** to **User library (all projects)** so it follows you across projects, or **Project (this project only)** to pin it to this design — that option needs the tab to have been opened from a `.netcrux-project`.

6. **Save and watch it repaint.**

    Click **Save**. The schematic repaints — every instance of that module type in the open design switches to the new shape immediately, with no re-elaboration.

!!! note "Project beats user on a collision"

    If a project defines its own symbol for the same module type, that **project symbol shadows** your user-library one for that project — so a team can pin a house style without disturbing your personal default.

## Where to go next {#next}

[Custom cell symbols](customizing.md) documents the editor, the sanitizer and the scope rules in full.
