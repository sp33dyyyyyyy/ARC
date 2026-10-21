--!strict
-- CollectionService tag names. Always use these constants instead of string literals.

return table.freeze({
	Hold = "Hold", -- a grabbable hold (BasePart with HoldType/Quality/HandOK/FootOK attributes)
	Climbable = "Climbable", -- a surface you can free-climb on by raycast (Stage 2)
	Bolt = "Bolt", -- lead-climbing bolt to clip a quickdraw into (Stage 4)
	Anchor = "Anchor", -- top/belay anchor (Stage 4)
	CrackPlacement = "CrackPlacement", -- spot for cams/nuts (Stage 7d)
	RouteStart = "RouteStart", -- start pad of a route (Stage 5)
	RouteSummit = "RouteSummit", -- summit volume of a route (Stage 5)
	CrashMat = "CrashMat", -- landing on this softens falls (Stage 3)
	Ledge = "Ledge", -- a ledge on a big wall: climbers pass through it, and can stand on it
})
