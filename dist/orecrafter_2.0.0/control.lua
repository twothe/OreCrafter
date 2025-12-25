require("lib/lib")

orecrafter=orecrafter or {}
orecrafter.initial_size={8,8}

local itemsToRemove = { "mining-drill", "furnace" }

local function ItemPrototype(name)
	if(prototypes and prototypes.item)then return prototypes.item[name] end
	if(game and game.item_prototypes)then return game.item_prototypes[name] end
	return nil
end

local function EntityPrototype(name)
	if(prototypes and prototypes.entity)then return prototypes.entity[name] end
	if(game and game.entity_prototypes)then return game.entity_prototypes[name] end
	return nil
end

local function PlanetNameFromSurface(surface)
	if(surface and surface.planet and surface.planet.name)then return surface.planet.name end
	return surface and surface.name or nil
end

local function BootstrapRecipeName(planet_name)
	if(planet_name=="nauvis")then return "orecrafter_bootstrap" end
	return "orecrafter_bootstrap-"..planet_name
end

local function EnsureGlobalState()
	if(not global)then global={} end
	global.orecrafter_bootstrap_unlocked=global.orecrafter_bootstrap_unlocked or {}
end

local function EnsureBootstrapUnlocked(surface,force)
	if(not surface or not force)then return end
	local planet_name=PlanetNameFromSurface(surface)
	if(not planet_name)then return end
	EnsureGlobalState()
	local force_table=global.orecrafter_bootstrap_unlocked[force.name] or {}
	if(force_table[planet_name])then return end
	local recipe_name=BootstrapRecipeName(planet_name)
	local recipe=force.recipes[recipe_name]
	if(recipe and not recipe.enabled)then
		recipe.enabled=true
	end
	force_table[planet_name]=true
	global.orecrafter_bootstrap_unlocked[force.name]=force_table
end

local function UnlockBootstrapForAllPlayers()
	EnsureGlobalState()
	for _,p in pairs(game.players)do
		EnsureBootstrapUnlocked(p.surface,p.force)
	end
end

events.on_init(function()
	events.raise_migrate()
	UnlockBootstrapForAllPlayers()
end)
events.on_config(function()
	UnlockBootstrapForAllPlayers()
end)
events.on_load(function() end)

local function StarterInventory(ev)
	local p=game.players[ev.player_index]
	local inv=p.get_main_inventory()
	if(not inv)then return end

	for k,v in pairs(inv.get_contents())do
		local item=ItemPrototype(k)
		local ent
		local place_name=item and (item.place_result or item.name)
		if(place_name)then ent=EntityPrototype(place_name) end
		if(ent and table.HasValue(itemsToRemove,ent.type))then --ent.type=="mining-drill")then
			inv.remove{name=k,count=v}
		end
	end

	EnsureGlobalState()
	if(not global.first)then global.first=true else return end

	inv.insert{name="assembling-machine-2",count=1}
	inv.insert{name="assembling-machine-1",count=4}
	inv.insert{name="small-electric-pole",count=5}
	inv.insert{name="orecrafter-fusiongenerator",count=1}

end
script.on_event(defines.events.on_cutscene_cancelled, StarterInventory)
script.on_event(defines.events.on_player_created, StarterInventory)

local function OnPlayerSurfaceChanged(ev)
	local p=game.players[ev.player_index]
	if(not p)then return end
	EnsureBootstrapUnlocked(p.surface,p.force)
end

script.on_event(defines.events.on_player_changed_surface, OnPlayerSurfaceChanged)
script.on_event(defines.events.on_player_created, OnPlayerSurfaceChanged)

lib.lua()
