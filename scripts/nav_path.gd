class_name NavPath
extends RefCounted

# Path finding over the waypoint graphs ({pos: Array[Vector3], links: Array, doors: Array}) that
# house.nav_graph() and the open maps build. Used by the run-away bottles and the chaser.


# Index of the waypoint closest to `pos`; heights count three times so another floor is "far".
static func nearest_node(graph: Dictionary, pos: Vector3) -> int:
	var positions: Array = graph["pos"]
	var best := -1
	var best_cost := INF
	for i in positions.size():
		var p: Vector3 = positions[i]
		var cost := Vector2(p.x - pos.x, p.z - pos.z).length() + absf(p.y - pos.y) * 3.0
		if cost < best_cost:
			best_cost = cost
			best = i
	return best


# Shortest route from waypoint `from` to waypoint `to` (both included); empty when there is none.
static func find_path(graph: Dictionary, from: int, to: int) -> Array[int]:
	var positions: Array = graph["pos"]
	var links: Array = graph["links"]
	var dist := PackedFloat32Array()
	dist.resize(positions.size())
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(positions.size())
	prev.fill(-1)
	dist[from] = 0.0
	var open: Array[int] = [from]
	var done := {}
	while not open.is_empty():
		var best_k := 0
		for k in open.size():
			if dist[open[k]] < dist[open[best_k]]:
				best_k = k
		var cur: int = open.pop_at(best_k)
		if cur == to:
			break
		if done.has(cur):
			continue
		done[cur] = true
		for n in links[cur]:
			var next: int = n
			var cost := dist[cur] + (positions[cur] as Vector3).distance_to(positions[next])
			if cost < dist[next]:
				dist[next] = cost
				prev[next] = cur
				open.append(next)
	var result: Array[int] = []
	if from != to and prev[to] == -1:
		return result
	var at := to
	while at != -1:
		result.push_front(at)
		at = prev[at]
	return result
