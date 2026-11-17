# Update Notes

## Doors
- Main house doors now use the supplied `DoorAnimate.fbx` opening/closing animation instead of rotating the mesh around its own axis (which made the panel collapse and lie flat).
- The animated door is fitted to the doorway: the panel is scaled to the doorway's width/height and its hinge edge is placed on the door frame, so it swings into the room like a real door.
- The physical bone simulator on the door model is disabled; the door is posed by the animation only.
- The blocking collider is disabled while the door is open, and a persistent interaction area over the doorway lets the player close the door again.
- Fixed the source door panel being hidden while the animated door is active.

## Mobile controls (Call of Duty Mobile style)
- Left side: fixed movement joystick at the bottom-left, with a translucent base.
- Right side: fixed look/turn joystick at the bottom-right (yaw and pitch).
- Three icon buttons along the upper edge of the right joystick:
  - Sprint: tap to toggle sprint on/off (green tint while active).
  - Flashlight: tap to toggle the flashlight (yellow tint while on). The flashlight button now works because touch-to-mouse emulation is enabled and the fill light is toggled with the spot light.
  - Stance: tap once to crouch, twice to lie prone, three times to stand. The icon and label change with the stance.
- Attack (fist) and Interact (hand) buttons sit to the left of the right joystick with icons.
- Minimap moved to the top-right corner so it no longer overlaps the look joystick.
- Camera height and movement speed follow the stance (crouch ~62% eye height, prone ~30%, slower movement).

## Enemy
- Enemy is scaled to human size (capsule 0.9 m tall, navigation agent radius 0.4).
- Replaced the T-pose/procedural arm swing with animations retargeted from the Universal Animation Library to the zombie skeleton:
  - idle, walk, jog, sprint, punch attack, hit reaction, death.
- Locomotion animation is chosen from the enemy's actual velocity; attack plays a punch/chainsaw thrust.
- Fixed enemy facing direction (the zombie model faces +Z) and removed the sideways body tilt.
- Chainsaw is attached to the right hand with a human-scale size and a raised-blade grip; the duplicate no-blood chainsaw and its physics bones are disabled.

## Files
- `script/doors/animated_door.gd`, `script/doors/door_interaction_area.gd`
- `script/house_interactions.gd`, `script/interactive_prop.gd`
- `script/player/player.gd`
- `script/enemy/enemy.gd`
- `scenes/touch_controllers.tscn`, `scenes/enemy.tscn`, `scenes/world.tscn`
- `addons/virtual_joystick/*`
- `assets/models/door/*`, `assets/animations/enemy/zombie_animations.tres`, `assets/ui/icons/*`


## Storage and pickups
- Added smooth hinged motion for ten identified cabinet-panel meshes in the imported furniture assembly, plus sliding motion for three drawer-box meshes. Drawers slide 0.42 m toward the player and return to their original position when closed; open panels disable their blocking collider until closed.
- Opening a cabinet panel or drawer reveals one pickup near the player's side of the storage. Drops cycle through metal scrap, bandages and first-aid kits. The level also has loose metal scrap and a bandage collectible on the floor.
- Added a reusable pickup scene with a visible floating/spinning item, pickup glow, a specific on-screen prompt, and collision/raycast interaction. The existing key now uses a clear pickup prompt and collection animation.
- Duplicate materials stack in the inventory; their count is shown beside the item name.
- Fixed the player interaction raycast so it assigns colliders that already implement `interact()` and keeps the Interact action outside the “no ray hit” branch. This restores both keyboard and touch pickup interactions.
- Added `script/items/pickup_item.gd`, `scenes/pickup_item.tscn`, and scrap/bandage inventory icons. Updated `house_interactions.gd`, `interactive_prop.gd`, `player.gd`, `Inventory.gd`, `item_list.gd`, `key.gd`, and `world.tscn`.

## Healing consumables
- Bandages restore up to 25 health and first-aid kits restore up to 60, capped at the player's maximum health. Healing is disabled for a dead player.
- Healing items are only consumed when they restore health; using one at full health leaves it in the inventory.
- Consumable inventory slots can be tapped/clicked to use. Added a mobile bag button to open the inventory, and paused player movement while the inventory is open.
- Storage loot cycles predictably, including first-aid kits and bandages. Added the first-aid-kit pickup model treatment and `assets/ui/icons/first_aid_kit.svg`.


## Island map and traversal safety
- Replaced the unbounded fall-off area with a finite island: the existing neighborhood is surrounded by a rocky coast and water, with a segmented collision barrier that keeps the player on land.
- Added static triangle collision to the major visible ground meshes and a broad, hidden safety floor beneath the measured map footprint.
- Added measured threshold ramps where the entrance floors differ in height; the open front door clears its blocking collider. Cabinet panels and drawers likewise disable their blockers while open.
- Validation: headless Godot scene parsing succeeded; 81/81 map grid rays found ground support; the real player body crossed the open doorway and was stopped before the shoreline barrier.
- Expanded terrain collision to both broad neighborhood planes and all three road meshes; the hidden catch floor remains only a last-resort stop beneath the playable footprint.
