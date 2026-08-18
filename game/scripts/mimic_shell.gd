extends StaticBody3D
class_name MimicShell

# The Perëkozhnik's DISGUISE — the outside of the lie.
#
# It holds the geometry of an ordinary prop the player has already met (a bottle on the
# kitchen shelf, a phone on the switchboard desk) and nothing else. E on it drops the
# disguise; `creature_shapechanger.gd` owns what happens next.
#
# ⚠️ IT IS DELIBERATELY *NOT* UNDER THE `ScaryObject`. `player.gd:_find_scary_object()`
# walks UP from the collider it hit, so a disguise parented under the creature's own
# ScaryObject would charge the Perëkozhnik's 16 panic/s for staring at a bottle — in the
# one level with no decay at all. Being a sibling is what makes the disguise cost nothing
# to look at, which is the only way "count the bottles" can be a fair thing to ask.
#
# ⚠️ It has no `can_interact()`, so the prompt appears exactly as it would on the real
# prop it is imitating. A mimic that refused E would be identifiable without touching it.

signal touched


func interact() -> void:
	touched.emit()
