Original short UI tones synthesized for CatPuzzle (猫咪占领火星).
They are original works in this repository and ship under the same LICENSE
as the rest of the project.

All cues share one tonal world (C major), one format (44.1 kHz / 16-bit /
stereo), attacks under 3 ms with no lead-in noise, and no energy below
110 Hz (phone speakers cannot reproduce it). Peak levels are deliberately
tiered by how important and how frequent each cue is.

- sfx_start.wav            1000ms  -9.0 dBFS   new level begins: rising
                                               C5-E5-G5-C6 arpeggio landing
                                               on a bright C6/E6/G6 chord
- sfx_excluded_mark.wav      95ms -10.5 dBFS   single-tap places x: short
                                               wooden G5 tick, decays clean
                                               so drag-marking a row reads
                                               as an even rhythm
- sfx_excluded_unmark.wav    58ms -13.0 dBFS   single-tap clears x: shorter,
                                               darker G5->D5 fall
- sfx_cat_mark.wav          460ms  -9.0 dBFS   double-tap places a paw: C6+G6
                                               bell pair, then a rising
                                               E5->A5 glide with vibrato left
                                               ringing as the feline tail
- sfx_cat_unmark.wav        200ms -12.0 dBFS   double-tap clears a paw:
                                               falling G6->C6 bell pair
- sfx_cat_failed.wav        300ms -10.0 dBFS   illegal cat placement: falling
                                               A4->F4 reed pair, detuned
                                               +20 cents for a sour beat
- sfx_heart_broken.wav      850ms  -9.0 dBFS   mistake limit hit, game lost:
                                               C5-G4-D#4 descent collapsing
                                               into a low C minor chord with
                                               a falling sigh

Regenerate with: python3 Scripts/synth_sounds.py  (numpy + scipy)
