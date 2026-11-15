# The agent door

A local API through which an agent on the same Mac (Claude, Codex, a script) looks at what mac4DSTEM's windows show. The app
is the MCP server itself, over HTTP at `http://127.0.0.1:47811/mcp`; nothing is installed beside it. This version is
read-only: the agent looks, the person drives.

The door itself (listener, token, Settings section, window list, MCP endpoint) is MacEMUI's `ShellAgentDoor` (MacEMUI
`docs/agent-door.md`), shared with macTEM. This app hands the door its tools.

## What an agent can do

| Tool | Answer |
|---|---|
| `get_workflow_guide` | how a person works through a scan here and how to judge each step (topics overview, calibration, disks, phase_mapping); read first (#236) |
| `list_windows` | the open windows: id, file, workspace and task, whether a run is in progress (the door's own tool) |
| `get_window` | dataset and loaded view, calibration and its verdict, task and its settings, running operation, displayed result with provenance, disk-detection parameters and statistics, saved results, recipe steps |
| `get_result_image` | the result figure File > Export writes: colour scale, scale bar, caption |
| `get_pattern_image` | the diffraction pattern as its pane shows it; the detector outlined in the Virtual Detector task, the detected disks drawn in the Disks task; `disks` false leaves them off, `crop_x`/`crop_y`/`crop_half` cut and magnify a square of detector pixels (#234) |
| `get_detected_disks` | the detected disks of the pattern on screen |
| `get_pattern_values` | the raw counts in a box around a detector pixel, its brightest pixel and the box edge's median (local background), to tell a weak disk from noise (#234) |
| `get_lineage` | the recipe and its run graph |
| `get_precipitate_objects` | the precipitate object table |
| `get_log` | the Output lines |

A window is `w1`, `w2`, ... (or none while one window is open). Pictures take `scale` 1...3; the pattern picture is drawn at
2 or more, as a Retina screen shows the pane, so the disk rings stand out as they do there (#185).
Every picture and number comes from the code that draws or exports it for the person, so the agent judges what the person sees.
Text the door writes itself (the calibration items, the spot-distortion summary, its own notes) uses a point whatever the
Mac's Region. The status line, the Output lines and `log_tail` are the window's own text, as the person reads it, so a Mac
set to German writes "6,5 px" and "189.173 peaks" (189173) there: read numbers from the JSON fields, not from those lines
(#323). Busy is one answer: `list_windows` and `get_window` both say busy while an operation runs, while a file opens (from
`open_file`'s answer on, the open's whole-cube pass included) and while the EDS room works; a step that failed after it
started puts its reason in `operation.error` until the next one begins (#266, #323). Settings carry the recipe's names (subpixel
`pixel`, `poly`, `multicorr`) in `get_window` and `task_settings` alike; `session.sidecar_unreadable` says why a session file
beside the dataset could not be read, where `has_sidecar` alone would say there is none (#233).

### Tools that act

Behind a second switch, Settings > Agents > "Let agents run analyses", off by default. The agent's client asks the person
before each call (MCP marks them as not read-only). One run at a time; Stop in the window cancels it.

| Tool | Does |
|---|---|
| `select_scan_position` | shows the pattern at scan position x, y, as a click on the scan map does |
| `get_probe_kernel` | (looks) the probe radius and where it came from, the kernel built or null, the detector and threshold |
| `set_probe_radius` | the Probe radius field; a synthetic kernel already built is rebuilt at it |
| `build_probe_kernel` | Build Kernel: synthetic, from the pattern on screen, or the file's probe (the vacuum scan stays with the person) |
| `set_detector` | classical or neural net, and the neural net's threshold |
| `set_disk_detection` | sets the Disks fields it names (spacing, relative and absolute thresholds and their reference, smoothing of pattern and correlation, correlation power, edge, max peaks, subpixel `pixel`/`poly`/`multicorr` and its upsampling, #235); live detection follows (it says so when no probe kernel is built yet) |
| `run_task` | presses Run for the window's task |
| `stop_run` | presses Stop |

Every one of these writes an Output line that starts "An agent", so the person can tell the agent's values from their own.
When an action moves a setting the agent did not name, the Output says so: measuring the probe (Build Kernel, a probe radius,
Calibrate Origin) sets `min_peak_spacing` to fit the probe when nobody has chosen one, and writes "Build Kernel also changed
disk detection: min_peak_spacing 16 → 4". `get_probe_kernel` carries the disk settings too (#232). A name or path the agent
gave stands in those lines in quotes (#310).

### The Agent folder (batches)

The person chooses one folder in Settings > Agents > Agent folder. Nothing outside it is listed, opened or written; paths
that lead out (`..`, links) are refused.

| Tool | Does |
|---|---|
| `list_agent_folder` | the files in the folder and its subfolders (looks only) |
| `open_file` | opens one in the window, as File > Open does (needs "Let agents run analyses"); as there, a spectrum image opened in a window that holds a 4D scan, or a 4D file in a window that holds only a spectrum image, opens in a new window, which `list_windows` then names (#323) |
| `save_result_image` | saves the displayed result there as File > Export > Result Image does, with its provenance; needs "Let agents save results there" too, off by default; a name that exists is refused, so no file is ever replaced |

A batch is a loop: `list_agent_folder`, then for each file `open_file`, the run tools, `save_result_image`.

## Turning it on

1. In mac4DSTEM: Settings > Agents > "Let agents on this Mac look at open windows". Off by default.
2. Press Copy Connection Command and paste it into Terminal once. It registers the app with Claude Code as an HTTP MCP
   server, with the port (mac4DSTEM asks for 47811) and the token. Cursor and VS Code take the same address and header.
   Claude desktop connects through MacEMUI's extension (`mac4DSTEM.mcpb`, MacEMUI `DesktopExtension/`).
3. New Token shuts out whoever had the old one; copy the command again after it.
4. For tools that act, also turn on "Let agents run analyses". The agent's client asks before each such call.

Notes from the first real-agent run (#237):
- The token reaches an agent only through the person (the copied command). That is on purpose: nothing else on the Mac can
  read it, and an agent in a sandbox cannot either.
- Pictures come back inside the tool's answer (PNG); the agent can keep them itself. The Agent folder is only for saving
  results beside the data, behind its own switch.
- A copy of the app with another bundle id (a test or drive build) keeps its own settings, so both switches start off there.
  A build signed only ad hoc does not launch (library validation); sign it with the team.
- An agent should call `get_workflow_guide` first (#236).

## How it is kept local

- The app listens on the loopback address (127.0.0.1) only, and only while the switch is on.
- A request needs the token, kept in the app's preferences until New Token. Requests from web pages (an `Origin` header) and
  requests whose `Host` is not the door's own are refused.
- The sandboxed app needs `com.apple.security.network.server` to listen at all. The app still sends nothing by itself.

## Code

`mac4DSTEM/App/AgentDoor/`: `Mac4DSTEMAgentDoor` (the door and the tools that look), `AgentDoorSnapshot` (what a window says), `AgentDoorRuns` (the
tools that act), `AgentDoorFolder` and `AgentFolder` (the Agent folder).
Settings > Agents is MacEMUI's `AgentDoorSettingsSection`.

## Coverage

`mac4DSTEM/App/AgentDoor/AgentDoorCoverage.swift` lists every control in the UI, by its accessibility identifier, with how an
agent reaches it: the tool that does it, already seen in `get_window` or a picture, left to the person on purpose (with the
reason), or a gap with its open issue (#224 to #230, #192). `AgentDoorCoverageTests` fails when a control has no row, so a
new control cannot ship until someone decides. Today 34 controls have a tool, 95 are seen, 47 stay with the person and 90
are gaps.

## Not yet

The CIF-in orientation search as a tool (issue #192), once CIF in is in the app.

## Task and Phase mapping (issue #209)

Behind "Let agents run analyses", like every tool that acts:

| Tool | What it does |
|---|---|
| `select_task` | moves the window to a task (`Disks`, `Phase mapping`, ...) or a workspace (`prepare`, `braggDisks`, `map`, ...), as the sidebar does; nothing runs; `can_run` says whether the task has a Run |
| `set_phase_mapping` | Phase mapping's reference-library and matching fields, only the ones given; a new classifier resets the intensity floor, as the picker does; `orientation_source` is `structures` (the default) or `typedZones`, as Advanced > Typed zone axes does (#192) |
| `scale_phase_matching_to_detector` | Scale to This Detector: the tolerances to one detector pixel; needs a physical Q pixel size |

`get_window`'s `view.task_settings` now carries Phase mapping's phases, settings, their size in detector pixels and why it
cannot run yet, and Diffraction groups' settings.

## The phase list (issue #192)

Behind "Let agents run analyses". A phase is named by its `index` in `phase_mapping.phases` (from 0), since the same
structure can be in the list twice with typed zone axes.

| Tool | What it does |
|---|---|
| `add_phase` | a CIF in the Agent folder becomes a phase, as Add Phase > From CIF file does; the first phase is the matrix, `is_matrix` makes this one it; a file that does not read is refused in words, no modal |
| `set_phase` | one phase: `is_matrix` (exactly one is; the matrix moves by marking another), its own `excitation_slab_inv_angstrom` or `clear_excitation_slab` back to the default, and with typed zone axes `zone_axis` and `orientation_relationship` |
| `remove_phase` | the minus button (Edit > Undo puts it back); removing the matrix makes the first phase the matrix |

`phase_mapping` also says the `orientation_source`, the `default_excitation_slab_inv_angstrom` an empty field means, and
`last_run`: positions per phase, matrix, indexed, not indexed and no data, the relationships a structures run learned, the
slab each phase was searched with, the reach, whether the settings changed since, and the evidence at the selected scan
position. The reach is `max_q_inv_angstrom` (capped at the detector's edge).

## Calibration (issue #208)

Behind "Let agents run analyses", like every tool that acts:

| Tool | What it does |
|---|---|
| `set_calibration` | types the Q pixel size, the R pixel size (each with its unit) and the voltage, as Prepare's fields do; recorded as manual |
| `run_calibration` | starts Calibrate Origin, Origin from Bragg Peaks, Fit Ellipse (in the fit annulus given) or Measure R–Q Rotation |

Each answers with the calibration as `get_window` shows it, or says the step started. Clear Calibration stays with the person.

## EDS in the Spectroscopy room (issue #254)

The room is MacEMUI's, shared with macEM, and so are its tools (`EDXAgentTools`, written once and registered by both apps).
They work on a spectrum image opened alone or beside a 4D scan. `select_task` with workspace `spectroscopy` moves the window
to the room first.

| Tool | What it does |
|---|---|
| `get_eds` | what the room holds: the file, the picked elements and their roles, the region, the kept regions, each line window's net counts with σ, Auto ID's suggestions and, once Quantify has run, the results table (the room's CSV: k-factors, wt% and at% with their uncertainties) or why the fit failed |
| `set_eds` | picks and removes elements, sets an element's role (quantify or fit only) and chooses the region: the whole map, a rectangle or ellipse in scan pixels, or a kept region by name; behind "Let agents run analyses" |
| `run_eds` | Auto ID, Quantify or Stop; answers at once, `get_eds` says busy until done; behind "Let agents run analyses" |

`run_task` in the room presses Quantify, as the toolbar does, with or without a 4D scan.

## Materials Project (issue #297)

| Tool | What it does |
|---|---|
| `fetch_materials_project` | fetches a material by its id (`mp-…`), as the sheet's Fetch does, and checks it against an expected formula and space group; answers at once; behind "Let agents run analyses", since it goes online |
| `get_materials_project` | whether the person has stored a key, and the last fetch: the material (formula, space group, cell, deprecated), the verdict and whether it may be imported, or why it failed |
| `import_materials_project` | the sheet's Import: as a phase of Map Phases or as ACOM's phase model; refused on a mismatch |

The request uses the key the person stored in Settings. The key never passes through the door: no tool reads, returns, sets
or logs it, and saving or removing it stays the person's.
