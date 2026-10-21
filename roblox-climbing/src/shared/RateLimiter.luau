--!strict
-- RateLimiter: token bucket per key (e.g. per player). Pure Luau, unit tested offline.
--
--   local limiter = RateLimiter.new(20, 30)   -- 20 requests/second, bursts of up to 30
--   if not limiter:allow(player) then return end

export type RateLimiter = {
	rate: number,
	burst: number,
	buckets: { [any]: { tokens: number, last: number } },
	allow: (self: RateLimiter, key: any, now: number?) -> boolean,
	forget: (self: RateLimiter, key: any) -> (),
}

local RateLimiter = {}

local function allow(self: RateLimiter, key: any, now: number?): boolean
	local t = now or os.clock()
	local bucket = self.buckets[key]
	if bucket == nil then
		bucket = { tokens = self.burst, last = t }
		self.buckets[key] = bucket
	end
	bucket.tokens = math.min(self.burst, bucket.tokens + (t - bucket.last) * self.rate)
	bucket.last = t
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

local function forget(self: RateLimiter, key: any)
	self.buckets[key] = nil
end

function RateLimiter.new(rate: number, burst: number): RateLimiter
	assert(rate > 0 and burst >= 1, "RateLimiter needs rate > 0 and burst >= 1")
	return {
		rate = rate,
		burst = burst,
		buckets = {},
		allow = allow,
		forget = forget,
	}
end

return table.freeze(RateLimiter)
