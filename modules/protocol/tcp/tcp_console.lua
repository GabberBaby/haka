-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local list = require('list')

require('protocol/ipv4')

local TcpConnInfo = list.new('tcp_cnx_info')

TcpConnInfo.field = {
	'id', 'srcip', 'srcport', 'dstip', 'dstport', 'state',
	'in_pkts', 'in_bytes', 'out_pkts', 'out_bytes'
}

TcpConnInfo.key = 'id'

TcpConnInfo.field_format = {
	['in_pkt']    = list.formatter.unit,
	['in_bytes']  = list.formatter.unit,
	['out_pkt']   = list.formatter.unit,
	['out_bytes'] = list.formatter.unit
}

function TcpConnInfo.method:drop()
	for _,r in ipairs(self._data) do
		local id = r._id
		hakactl.remote(r._thread, function ()
			local tcp = package.loaded['protocol/tcp_connection']
			if not tcp then error("tcp protocol not available", 0) end
			tcp.console.drop_connection(id)
		end)
	end
end

function TcpConnInfo.method:reset()
	for _,r in ipairs(self._data) do
		local id = r._id
		hakactl.remote(r._thread, function ()
			local tcp = package.loaded['protocol/tcp_connection']
			if not tcp then error("tcp protocol not available", 0) end
			tcp.console.reset_connection(id)
		end)
	end
end

console.tcp = {}

function console.tcp.connections(show_dropped)
	local data = hakactl.remote('all', function ()
		local tcp = package.loaded['protocol/tcp_connection']
		if not tcp then error("tcp protocol not available", 0) end
		return tcp.console.list_connections(show_dropped)
	end)

	local conn = TcpConnInfo:new()
	conn:addall(data)
	return conn
end
