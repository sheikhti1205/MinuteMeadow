# Companion animation

The companion engine is a separate Flutter module. It accepts a validated rig and companion events. Timer state stays in the productivity engine, so playback cannot affect a session.

A rig describes a canvas and a set of layers. Each layer refers to an atlas region and may name a parent. Parent transforms affect children, while draw order determines overlap independently of parenting. Visibility, opacity, translation, rotation, scale and frame selection can vary per layer.

Clips are timed data. A looping clip returns to its start; a one-shot clip emits completion and returns to the default state unless another transition takes precedence. Use explicit events for interaction milestones such as a catch. Use elapsed time to advance playback, and stop the render ticker when the app goes into the background.

Movement and hitboxes belong to the scene, not the artwork. A ball can follow a scripted trajectory while an actor moves to intercept it. The scene emits catch and return events; the rig determines which frames or transforms to display.

In a debug build, open **Settings → Animation laboratory** and choose **Run route** to exercise walking, running, and jumping. Turn on **Hitboxes** to see the interaction bounds move with the actor. If the rig supplies `walk`, `run`, or `jump` clips, the lab plays them during the corresponding movement.

## Rig documents

A standalone rig has `schemaVersion: 1`, `canvas` (`width` and `height`), `atlases`, `layers`, `clips` and an optional `defaultClip`.

- Each atlas names an `id`, pixel dimensions and an optional `imageKey` for the asset loader.
- Layers are listed in draw order. Each has an `id` and `frame` (`atlas`, `x`, `y`, `width`, `height`). Layer properties include `parent`, `offset`, `pivot`, `rotationDegrees`, `scale`, `opacity` and `visible`. Points are objects with `x` and `y`.
- Clips name an `id`, `durationMs`, `loop` and layer tracks. Each track targets a `layer`. Frame sequences provide an array of regions and a `frameDurationMs`. Transform tracks provide a `property` and ordered `keyframes`, each with `timeMs`, `value` and `easing` (`linear` or `step`).

The rig validator checks layer cycles, atlas references and frame bounds before opening a preview. Installed pack authors use the [pack manifest](COMPANION_PACK_SPEC.md); the app converts it into the same rig model.
