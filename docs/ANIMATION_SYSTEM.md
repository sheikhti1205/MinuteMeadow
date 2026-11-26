# Companion animation

The companion engine is planned as a separate Flutter module. It accepts a validated rig and companion events. Timer state remains in the productivity engine, so a stalled or disabled animation cannot affect a session.

A rig describes a canvas and a set of layers. Each layer refers to an atlas region and may name a parent. Parent transforms affect children, while draw order determines overlap independently of parenting. Visibility, opacity, translation, rotation, scale and frame selection can vary per layer.

Clips are timed data. A looping clip returns to its start; a one-shot clip emits completion and returns to the default state unless another transition takes precedence. Use explicit events for interaction milestones such as a catch. Use elapsed time to advance playback, and stop the render ticker when the app goes into the background.

Movement and hitboxes belong to the scene, not the artwork. A ball can follow a scripted trajectory while an actor moves to intercept it. The scene emits catch and return events; the rig determines which frames or transforms to display.
