-- Tiny 2D vector helpers. Vectors are {x, y} tables; nothing is changed in place.
local V = {}

function V.new(x, y) return { x, y } end
function V.add(a, b) return { a[1] + b[1], a[2] + b[2] } end
function V.sub(a, b) return { a[1] - b[1], a[2] - b[2] } end
function V.scale(a, s) return { a[1] * s, a[2] * s } end
function V.dot(a, b) return a[1] * b[1] + a[2] * b[2] end
function V.len(a) return math.sqrt(a[1] * a[1] + a[2] * a[2]) end
function V.dist(a, b) return V.len(V.sub(a, b)) end

function V.unit(a)
  local l = V.len(a)
  if l < 1e-15 then return { 0, 0 } end
  return { a[1] / l, a[2] / l }
end

-- Angle between two vectors, degrees.
function V.angle(a, b)
  local c = V.dot(V.unit(a), V.unit(b))
  if c > 1 then c = 1 elseif c < -1 then c = -1 end
  return math.deg(math.acos(c))
end

-- Solves the 2x2 system [a b; c d] x = r. Returns nil if singular.
function V.solve2(a, b, c, d, r)
  local det = a * d - b * c
  if math.abs(det) < 1e-300 then return nil end
  return { (r[1] * d - b * r[2]) / det, (a * r[2] - c * r[1]) / det }
end

return V
