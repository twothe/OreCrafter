require("lib/lib")

orecrafter=orecrafter or {}
orecrafter.initial_size={8,8}

events.on_init(function() events.raise_migrate() end)
events.on_config(function() end)
events.on_load(function() end)

local itemsToRemove = { "mining-drill", "furnace" }

local function StarterInventory(ev)
	local p=game.players[ev.player_index]
	local inv=p.get_main_inventory()
	if(not inv)then return end

	for k,v in pairs(inv.get_contents())do
		local item=game.item_prototypes[k]
		local ent
		if(item)then ent=game.entity_prototypes[item.name] end
		if(ent and table.HasValue(itemsToRemove,ent.type))then --ent.type=="mining-drill")then
			inv.remove{name=k,count=v}
		end
	end

	if(not global.first)then global.first=true else return end

	inv.insert{name="assembling-machine-2",count=1}
	inv.insert{name="assembling-machine-1",count=4}
	inv.insert{name="small-electric-pole",count=5}
	inv.insert{name="orecrafter-fusiongenerator",count=1}

end
script.on_event(defines.events.on_cutscene_cancelled, StarterInventory)
script.on_event(defines.events.on_player_created, StarterInventory)

lib.lua()
