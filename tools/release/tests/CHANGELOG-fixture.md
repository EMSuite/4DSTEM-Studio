## [5.3.1](https://github.com/EMSuite/4DSTEM-Studio/compare/v5.3.0...v5.3.1) (2026-11-14)


### Bug Fixes

* a cube from another file no longer shows the previous file's EDS maps ([#327](https://github.com/EMSuite/4DSTEM-Studio/issues/327)) ([345776b](https://github.com/EMSuite/4DSTEM-Studio/commit/345776b98d04afa6e5db52790e9543d26adbdd29)), closes [#322](https://github.com/EMSuite/4DSTEM-Studio/issues/322)
* a file the app may not read is refused as unreadable; StaleTaskJourney opens its fixture in place ([#359](https://github.com/EMSuite/4DSTEM-Studio/issues/359)) ([bf36437](https://github.com/EMSuite/4DSTEM-Studio/commit/bf364375850d5ec4d69a87b979061e513ebea27f))
* a new dataset starts with an empty phase list ([#317](https://github.com/EMSuite/4DSTEM-Studio/issues/317)) ([20b4414](https://github.com/EMSuite/4DSTEM-Studio/commit/20b4414c01a483cd92e5d5cb21691e4e0f5dfceb))
* a typed orientation relationship stands for all its variants in the matrix ([#358](https://github.com/EMSuite/4DSTEM-Studio/issues/358)) ([8c81635](https://github.com/EMSuite/4DSTEM-Studio/commit/8c816359bb425606ca9eb4ff67ab27abd44cb673))
* an empty virtual detector and an origin with no measured position are refused ([#343](https://github.com/EMSuite/4DSTEM-Studio/issues/343)) ([37e71e7](https://github.com/EMSuite/4DSTEM-Studio/commit/37e71e76e3d86ac0da9eb5d04f4fcf5fb21ff6d9))
* Calibrate Q from crystal reads diamond [110] rings from {111} (double-diffraction shells, DiffractoKit 0.16.0) ([#352](https://github.com/EMSuite/4DSTEM-Studio/issues/352)) ([28daf6b](https://github.com/EMSuite/4DSTEM-Studio/commit/28daf6b3f1be3d75649ba544ffce08f2d40a4176))
* calibrated Bragg vectors keep the count of positions where detection failed ([#328](https://github.com/EMSuite/4DSTEM-Studio/issues/328)) ([8042c20](https://github.com/EMSuite/4DSTEM-Studio/commit/8042c20e4ac5e7022440c86a08ebd75a6e167039)), closes [#302](https://github.com/EMSuite/4DSTEM-Studio/issues/302)
* fine-tuning scales a windowed pattern's dose as inference does ([#335](https://github.com/EMSuite/4DSTEM-Studio/issues/335)) ([fc654dd](https://github.com/EMSuite/4DSTEM-Studio/commit/fc654dd934f7907482b9ebf5ede8574a7a6a6f63))
* Fit Distortion from Spots fits Phase mapping's matrix, not the last added phase ([#316](https://github.com/EMSuite/4DSTEM-Studio/issues/316)) ([e174530](https://github.com/EMSuite/4DSTEM-Studio/commit/e174530878712855cc03320317b52182ea014979))
* opening a dataset writes nothing on its volume (read-only Recents bookmark) ([#329](https://github.com/EMSuite/4DSTEM-Studio/issues/329)) ([4d23857](https://github.com/EMSuite/4DSTEM-Studio/commit/4d2385712aad9dc27c3cbe1a0681a992b6e1e3bb))
* phase mapping refuses an origin that is not a measured beam centre ([#346](https://github.com/EMSuite/4DSTEM-Studio/issues/346)) ([7e14151](https://github.com/EMSuite/4DSTEM-Studio/commit/7e1415191155879d72bac273467a0ae7670b04b1))
* placing a virtual detector no longer moves the origin; Prepare sets a centre by hand ([#360](https://github.com/EMSuite/4DSTEM-Studio/issues/360)) ([899a12a](https://github.com/EMSuite/4DSTEM-Studio/commit/899a12a90759dbcbaf48fdf4cefcfdfd585889a1))
* **release:** new Sparkle update key after the keychain loss ([#287](https://github.com/EMSuite/4DSTEM-Studio/issues/287)) ([9252fb1](https://github.com/EMSuite/4DSTEM-Studio/commit/9252fb173907bfddc76e8c3d3951700c964685d3)), closes [#285](https://github.com/EMSuite/4DSTEM-Studio/issues/285)
* sidebar task rows and Workspace › Next/Previous Task choose the task through accessibility and the keyboard ([#319](https://github.com/EMSuite/4DSTEM-Studio/issues/319)) ([5db2ba1](https://github.com/EMSuite/4DSTEM-Studio/commit/5db2ba1041c2261ff8e6eb82e37a351b6a0580e7))
* the task bar shows one ellipsis, no rate, and a spaced Cancel ([#362](https://github.com/EMSuite/4DSTEM-Studio/issues/362)) ([d9ac2cf](https://github.com/EMSuite/4DSTEM-Studio/commit/d9ac2cf3c4fcdb56e1072f72c218d1e726fde8eb))
* the UI test runner keeps one signature in gate and drive runs ([#331](https://github.com/EMSuite/4DSTEM-Studio/issues/331)) ([0b35b25](https://github.com/EMSuite/4DSTEM-Studio/commit/0b35b25704b8b6c5b51575c420ab97337e431dfc))
* Thronsen A parity pin moves to the 98.59 % main reads (accepted drift) ([#354](https://github.com/EMSuite/4DSTEM-Studio/issues/354)) ([aae9cc8](https://github.com/EMSuite/4DSTEM-Studio/commit/aae9cc845125a1385a0cd5e4faedefc9d53537b5))
* Thronsen A parity pin moves to the 98.59 % main reads (accepted, [#345](https://github.com/EMSuite/4DSTEM-Studio/issues/345)) ([aae9cc8](https://github.com/EMSuite/4DSTEM-Studio/commit/aae9cc845125a1385a0cd5e4faedefc9d53537b5))

