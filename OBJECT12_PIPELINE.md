# Object 12 — 2D → 3D asset pipeline

Replacing Level 6's placeholder creature (currently `Void_creature.glb`, a Mixamo model
retinted grey-green) with a purpose-built model of Object 12.

**Input:** `monster_2d_front_view.png` (with `monster_2d_back_view.png` as fallback)
**Output:** rigged, animated `.glb` files in `game/assets/models/object12/`
**Tool:** [meshy.ai](https://www.meshy.ai) — credit-based; rigging/animation may need a paid tier

---

## 1 · Meshy — generate the mesh

1. meshy.ai → **Image to 3D** → upload `monster_2d_front_view.png` (front only, first pass).
2. Settings: **Symmetry on** · **Quad topology** · **~30k polys** · **PBR texture on**.
3. Generate the **preview** (cheap draft), then inspect all four risk points:
   - **Claws** — long and separated, not fused into mittens? *(most likely failure)*
   - **Hands** — clear of the thighs, not welded?
   - **Head** — closed volume, crown and gill-fan intact?
   - **Silhouette** — still reads as a figure at thumbnail size?
4. Cloth reconstructing as a solid skirt, and the open chest cavity filling in solid, are
   **expected** — accept both. Neither is visible at Level 6's light levels.
5. If the invented back is bad, re-run as a **multi-view** job with the back image added.
   ⚠️ The two views are not in identical poses, so only do this if the single-image back is
   genuinely unusable — a pose mismatch can blur the result rather than sharpen it.
6. Happy with the preview → **Refine + Texture at 2K**. Not 4K.

---

## 2 · Meshy — rig

1. On the finished model → **Rig / Animate**.
2. Place joints by the **underlying anatomy**, not the fungal growths — the shelf brackets are
   surface detail; the real shoulder sits beneath them.
3. Confirm the humanoid skeleton. Bone names don't matter.

---

## 3 · Meshy — animate

⚠️ **Turn on "in-place" / no root motion for every single clip.** The level drives position in
code (`CHASE_SPEED = 5.0`); an animation carrying its own translation will slide, drift and
desync from its collider.

| Clip | Drives | Must loop |
|---|---|---|
| `idle` | dormant spawn + `SEARCH` scanning | yes |
| `walk` | `PATROL`, `INVESTIGATE` | yes |
| `run` | `CHASE` — fast, aggressive | yes |
| `stagger` | `STAGGERED` (torch-blinded, 5–7 s) | yes, or hit-react + stunned idle |
| `attack` | contact kill at 1.0 m | no |
| `scream` *(optional)* | the incinerator purge | no |

Minimum viable set: **idle + walk + run + stagger.** The rest can be blended.

---

## 4 · Export

**glTF Binary `.glb`** · textures **embedded** · **Y-up** · one file per clip.

```
object12_base.glb      ← rigged mesh, no animation
object12_idle.glb
object12_walk.glb
object12_run.glb
object12_stagger.glb
object12_attack.glb
```

- **Never export FBX** — Godot 4 cannot import it without an external converter.
- Godot imports an animation-only `.glb` as an **Animation Library**, so separate files are the
  clean path here. Don't merge them.
- Target under ~20 MB total (the placeholder it replaces is 6.3 MB).

---

## 5 · Blender — only if something is broken

| Problem | Fix |
|---|---|
| Meshy gave FBX only | Import → `File > Export > glTF 2.0` → **glTF Binary**, **+Y Up**, enable Skinning + Animation |
| Wrong scale | Scale to **2.0 m** head-to-heel → `Ctrl+A > Apply > Scale` |
| Feet not at origin | Move soles to z=0 → `Ctrl+A > Apply > All Transforms` |
| 4K textures | Leave them — downscaling happens on the Godot side |

**Don't rotate it to "face forward."** glTF and Godot disagree on the forward axis; that is a
one-line fix on the visual root in `creature_object12.gd`.

---

## 6 · Hand off

Drop the files in `game/assets/models/object12/` and say **which clips you actually got**.
Then, on the code side:

1. Run `--import` — mandatory. New assets are invisible to `ResourceLoader` until Godot rescans.
2. Screenshot in-engine at real torch-light levels to verify the silhouette reads in the dark.
3. Rewrite `creature_object12.gd`'s visual layer:
   - **Kill `_apply_retint()`'s `material_override`.** It replaces the model's own textures
     wholesale — that is why the current creature renders as a featureless grey-green blob. The
     sickly palette and red vein emission move to a `next_pass` overlay or an albedo modulate so
     the real maps survive. `apply_light_damage()`'s wound flash gets rewired to whatever remains.
   - **Kill `_pose_arms_down()`.** The bone-rotation hack and its `mixamorig_*` name dependency
     exist only because the placeholder is a static T-pose with no animation.
   - Wire the clips to the five states via an `AnimationPlayer` + `AnimationLibrary`.
   - Retune the collider — the current capsule is 1.7 m tall × 0.3 m radius; this creature is
     taller and much thinner.

⚠️ `CONTACT_DIST = 1.0` is a **difficulty constant**, independent of the capsule. It does not
change without an explicit decision.

---

## Reference — why the odd constraints exist

| Constraint | Reason |
|---|---|
| A-pose, arms 40° out | Arms touching the hips make auto-riggers weld arm weights to the torso |
| Pale, never black | Dark-on-dark loses geometry in reconstruction, and Level 6 lights sit at ~0.45 energy — a black creature is invisible in the torch beam. Visibility is the *mechanic* in a pursuit level |
| No glow / no emission in the texture | Emission above 1.0 clamps to flat white here — no tonemapping, no bloom (ISSUES_SOLUTIONS Issue 21). The vein glow is added in code at 0.35 |
| Growths hug the body | Detail floating off the silhouette reconstructs as lumps or vanishes |
| Flat diffuse lighting, no rim light | Baked shadows burn into the albedo and then fight the real lighting in-engine |
| Head distinct from shoulders | The player identifies this thing as a shape in a beam at 10+ m; a head merged into shoulder growths stops reading as a figure |
