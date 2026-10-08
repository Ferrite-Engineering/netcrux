# Tiers & licensing

Licensing terms are the same for all four EDACrux products, so they live in one place on the suite site: **[edacrux.app/licensing](https://edacrux.app/licensing)**. It maps every feature to its tier and describes how the Education tier and license keys work.

What is specific to NetCrux:

- **Open Core** is the free, open-source schematic browser: elaboration, navigation, search, one-step tracing, annotations (from NetCrux 1.1), sessions, projects, workspaces, export and cross-probe.
- **Pro** <span class="tier tier-pro">Pro</span> adds the Cone of Influence, X-Trace, netlist diff, custom cell symbols, the RTL source pane, CDC, reset-domain and FSM analysis, the switching-activity heatmap, and cross-probing from the schematic context menu.
- **Enterprise** <span class="tier tier-enterprise">Enterprise</span> adds hosting collaborative schematic sessions, org-wide symbol libraries, org-wide policy and the audit log. From NetCrux 1.1, joining a session is free; hosting is Enterprise. A guest without a license is a full participant in the downloaded app. See [Collaborative sessions](collaboration.md) and [Administration](administration.md).
- **Education** <span class="tier tier-edu">EDU</span> grants the Pro feature set to verified students and educators for non-commercial use.

In the downloaded app, the license lives in `Settings → License`: paste a license key or the contents of a license file, or request an educational license. That panel is where a Pro, Enterprise or Education key goes; Open Core stays free and never asks for one.

Pro commands appear in the Open Core app's menus and command palette too, marked with a Pro badge. Open Core does not contain their implementation, so choosing one there shows a message that it requires NetCrux Pro. The web viewer, which is Open Core only, does not list them.
