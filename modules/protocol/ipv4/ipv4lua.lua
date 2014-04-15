-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--local ipv4 = require('protocol/ipv4')

local ipv4_dissector = haka.dissector.new{
	type = haka.dissector.EncapsulatedPacketDissector,
	name = 'ipv4'
}

local ipv4_addr_convert = {
	get = function (x) return ipv4.addr(x) end,
	set = function (x) return x.packed end
}

local option_header  = haka.grammar.record{
	haka.grammar.field('copy',        haka.grammar.number(1)),
	haka.grammar.field('class',       haka.grammar.number(2)),
	haka.grammar.field('number',      haka.grammar.number(5)),
}

local option_data = haka.grammar.record{
	haka.grammar.field('len',         haka.grammar.number(8))
		:validate(function (self) self.len = #self.data+2 end),
	haka.grammar.field('data',        haka.grammar.bytes()
		:options{count = function (self) return self.len-2 end})
}

local option = haka.grammar.record{
	haka.grammar.union{
		option_header,
		haka.grammar.field('type',    haka.grammar.number(8))
	},
	haka.grammar.optional(option_data,
		function (self) return self.type ~= 0 and self.type ~= 1 end
	)
}

local header = haka.grammar.record{
	haka.grammar.field('version',     haka.grammar.number(4))
		:validate(function (self) self.version = 4 end),
	haka.grammar.field('hdr_len',     haka.grammar.number(4))
		:convert(haka.grammar.converter.mult(4))
		:validate(function (self) self.hdr_len = self:_compute_hdr_len(self) end),
	haka.grammar.field('tos',         haka.grammar.number(8)),
	haka.grammar.field('len',         haka.grammar.number(16))
		:validate(function (self) self.len = self.hdr_len + #self.payload end),
	haka.grammar.field('id',          haka.grammar.number(16)),
	haka.grammar.field('flags',       haka.grammar.record{
		haka.grammar.field('rb',      haka.grammar.flag),
		haka.grammar.field('df',      haka.grammar.flag),
		haka.grammar.field('mf',      haka.grammar.flag),
	}),
	haka.grammar.field('frag_offset', haka.grammar.number(13)
		:convert(haka.grammar.converter.mult(8))),
	haka.grammar.field('ttl',         haka.grammar.number(8)),
	haka.grammar.field('proto',       haka.grammar.number(8)),
	haka.grammar.field('checksum',    haka.grammar.number(16))
		:validate(function (self)
			self.checksum = 0
			self.checksum = ipv4.inet_checksum_compute(self._payload:sub(0, self.hdr_len))
		end),
	haka.grammar.field('src',         haka.grammar.number(32)
		:convert(ipv4_addr_convert, true)),
	haka.grammar.field('dst',         haka.grammar.number(32)
		:convert(ipv4_addr_convert, true)),
	haka.grammar.field('opt',         haka.grammar.array(option)
		:options{
			untilcond = function (elem, ctx)
				return ctx.iter.meter >= ctx.top.hdr_len or
					(elem and elem.type == 0)
			end
		}),
	haka.grammar.padding{align = 32},
	haka.grammar.verify(function (self, ctx)
		if ctx.iter.meter ~= self.hdr_len then
			error(string.format("invalid ipv4 header size, expected %d bytes, got %d bytes", self.hdr_len, ctx.iter.meter))
		end
	end),
	haka.grammar.field('payload',     haka.grammar.bytes())
}

ipv4_dissector.grammar = header:compile()

function ipv4_dissector.method:parse_payload(pkt, payload)
	self.raw = pkt
	ipv4_dissector.grammar:parse(payload:pos("begin"), self)
end

function ipv4_dissector.method:create_payload(pkt, payload, init)
	self.raw = pkt
	ipv4_dissector.grammar:create(payload:pos("begin"), self, init)
end

function ipv4_dissector.method:verify_checksum()
	return ipv4.inet_checksum_compute(self._payload:sub(0, self.hdr_len)) == 0
end

function ipv4_dissector.method:next_dissector()
	return ipv4.ipv4_protocol_dissectors[self.proto]
end

function ipv4_dissector._compute_hdr_len(pkt)
	local len = 20
	if pkt.opt then
		for _, opt in ipairs(pkt.opt) do
			len = len + (opt.len or 1)
		end
	end
	return len
end

function ipv4_dissector.method:forge_payload(pkt, payload)
	if payload.modified then
		self.len = nil
		self.checksum = nil
	end

	self:validate()
end

function ipv4_dissector:create(pkt, init)
	if not init then init = {} end
	if not init.hdr_len then init.hdr_len = ipv4_dissector._compute_hdr_len(init) end
	pkt.payload:append(haka.vbuffer_allocate(init.hdr_len))

	local ip = ipv4_dissector:new(pkt)
	ip:create(init, pkt)

	return ip
end

return ipv4