lib={DATA_LOGIC=true}
require("lib/lib")

local hand=logic.hand
local orecrafter={}
local modname="__orecrafter__"

local function SortedKeys(t)
	local keys={}
	for k in pairs(t or {})do
		table.insert(keys,k)
	end
	table.sort(keys)
	return keys
end

function orecrafter.BuildTechDepthMap()
	local depth={}
	local visiting={}
	local function Resolve(tech_name)
		if(depth[tech_name]~=nil)then return depth[tech_name] end
		if(visiting[tech_name])then
			error("OreCrafter: technology prerequisite loop detected at '"..tostring(tech_name).."'.")
		end
		local tech=data.raw.technology and data.raw.technology[tech_name]
		if(not tech)then
			error("OreCrafter: unknown technology '"..tostring(tech_name).."' while evaluating resource outputs.")
		end
		visiting[tech_name]=true
		local best
		for _,prereq in pairs(tech.prerequisites or {})do
			local prereq_depth=Resolve(prereq)
			if(not best or prereq_depth<best)then best=prereq_depth end
		end
		visiting[tech_name]=nil
		local result=(best or 0)+1
		depth[tech_name]=result
		return result
	end
	for tech_name in pairs(data.raw.technology or {})do
		Resolve(tech_name)
	end
	return depth
end

function orecrafter.BuildOutputTechDepthMap()
	local tech_depth=orecrafter.BuildTechDepthMap()
	local recipe_unlock_depth={}
	for tech_name,tech in pairs(data.raw.technology or {})do
		local depth=tech_depth[tech_name]
		local effects=proto.TechEffects(tech)
		for _,recipe_name in pairs(effects.recipes)do
			local current=recipe_unlock_depth[recipe_name]
			if(not current or depth<current)then recipe_unlock_depth[recipe_name]=depth end
		end
	end

	local output_depth={}
	for recipe_name,recipe in pairs(data.raw.recipe or {})do
		local depth
		if(proto.IsEnabled(recipe))then depth=0 else depth=recipe_unlock_depth[recipe_name] end
		if(depth~=nil)then
			for _,ingredient in pairs(proto.Ingredients(recipe) or {})do
				local rs=proto.Ingredient(ingredient)
				local key=(rs.type or "item")..":"..rs.name
				if(output_depth[key]==nil or depth<output_depth[key])then output_depth[key]=depth end
			end
			for _,result in pairs(proto.Results(recipe) or {})do
				local rs=proto.Result(result)
				local key=(rs.type or "item")..":"..rs.name
				if(output_depth[key]==nil or depth<output_depth[key])then output_depth[key]=depth end
			end
		end
	end
	return output_depth
end

function orecrafter.OutputTechDepth(rs)
	local key=(rs.type or "item")..":"..rs.name
	return orecrafter.output_tech_depth and orecrafter.output_tech_depth[key] or 0
end

function orecrafter.SelectPrimaryResult(results,context)
	local candidates={}
	for index,result in ipairs(results or {})do
		local rs=proto.Result(result)
		if(not rs or not rs.name)then
			error("OreCrafter: invalid minable result for "..tostring(context)..".")
		end
		if(not proto.CraftingObject(rs))then
			error("OreCrafter: unknown minable result '"..tostring(rs.name).."' for "..tostring(context)..".")
		end
		local normalized=table.deepcopy(rs)
		if(not normalized.type)then normalized.type="item" end
		table.insert(candidates,{index=index,depth=orecrafter.OutputTechDepth(normalized),result=normalized})
	end
	if(#candidates==0)then
		error("OreCrafter: no valid minable results for "..tostring(context)..".")
	end
	table.sort(candidates,function(a,b)
		if(a.depth==b.depth)then return a.index<b.index end
		return a.depth<b.depth
	end)
	return candidates[1].result
end

--[[ orecrafter Crafting Logic - Fetch the earliest lab-able science pack ]]--
--[[ Do the thing to make a landfill recipe from the first lab-based science packs ]]--

orecrafter.initial_packs={}
logic.InitScanResourceCats()
logic.InitScanCraftCats()
logic.InitScanRecipes()
logic.InitScanTechnologies()
logic.ScanRecipes(true)
for k,v in pairs(hand.items) do
	if(proto.LabPack(k)) then
		local raw=proto.RawItem(k) orecrafter.initial_packs[k]=raw
	end
end

--[[ Do the thing with the resources and trees ]]--

orecrafter.recipes={}
orecrafter.basics={}
orecrafter.resources={tree={},raw={},oil={},chem={}}
orecrafter.matter_recipes={} -- smeltables

local function GetStartupBool(name,default_value)
	local setting=settings.startup[name]
	if(setting==nil or setting.value==nil)then return default_value end
	return (setting.value and true or false)
end

local function GetStartupNumber(name)
	local setting=settings.startup[name]
	if(setting==nil or setting.value==nil)then
		error("OreCrafter: missing startup setting '"..tostring(name).."'.")
	end
	return setting.value
end

orecrafter.restrict_planet_resources=GetStartupBool("orecrafter_restrict_planet_resources",true)
orecrafter.remove_natural_sources=GetStartupBool("orecrafter_remove_natural_sources",true)
orecrafter.planet_conditions={}
orecrafter.planet_resource_map={}
orecrafter.planet_tile_fluid_map={}
orecrafter.planet_control_map={}
orecrafter.plant_outputs={yumako=true,jellynut=true}
orecrafter.allow_water_duplication=GetStartupBool("orecrafter_allow_water_duplication",true)
orecrafter.settings={
	item_speed=GetStartupNumber("orecrafter_item_speed"),
	item_needed=GetStartupNumber("orecrafter_item_needed"),
	item_count=GetStartupNumber("orecrafter_item_count"),
	fluid_speed=GetStartupNumber("orecrafter_fluid_speed"),
	fluid_needed=GetStartupNumber("orecrafter_fluid_needed"),
	fluid_count=GetStartupNumber("orecrafter_fluid_count"),
}

orecrafter.temp={} -- a simple accumulator pending extend
function orecrafter.Extend()
	if(table_size(orecrafter.temp)>0)then
		local t={}
		for k,v in pairs(orecrafter.temp)do
			table.insert(t,v)
		end
		data:extend(t)
		orecrafter.temp={}
	end
end

function orecrafter.BuildPlanetConditions()
	local planet_conditions={}
	for planet_name,planet in pairs(data.raw.planet or {})do
		local props=planet.surface_properties
		if(props)then
			local conditions={}
			for _,property in ipairs(SortedKeys(props))do
				local value=props[property]
				if(type(value)=="number")then
					table.insert(conditions,{property=property,min=value,max=value})
				end
			end
			if(#conditions>0)then
				planet_conditions[planet_name]=conditions
			end
		end
	end
	return planet_conditions
end

function orecrafter.BuildPlanetResourceMap()
	local planet_resource_map={}
	for planet_name,planet in pairs(data.raw.planet or {})do
		local settings=planet.map_gen_settings and planet.map_gen_settings.autoplace_settings
		local entities=settings and settings.entity and settings.entity.settings
		if(entities)then
			for entity_name in pairs(entities)do
				if(data.raw.resource[entity_name])then
					planet_resource_map[entity_name]=planet_resource_map[entity_name] or {}
					planet_resource_map[entity_name][planet_name]=true
				end
			end
		end
	end
	return planet_resource_map
end

function orecrafter.BuildPlanetEntityMap()
	local planet_entity_map={}
	for planet_name,planet in pairs(data.raw.planet or {})do
		local settings=planet.map_gen_settings and planet.map_gen_settings.autoplace_settings
		local entities=settings and settings.entity and settings.entity.settings
		if(entities)then
			for entity_name in pairs(entities)do
				planet_entity_map[entity_name]=planet_entity_map[entity_name] or {}
				planet_entity_map[entity_name][planet_name]=true
			end
		end
	end
	return planet_entity_map
end

function orecrafter.BuildPlanetAutoplaceControlMap()
	local planet_control_map={}
	for planet_name,planet in pairs(data.raw.planet or {})do
		local controls=planet.map_gen_settings and planet.map_gen_settings.autoplace_controls
		if(controls)then
			for control_name in pairs(controls)do
				planet_control_map[control_name]=planet_control_map[control_name] or {}
				planet_control_map[control_name][planet_name]=true
			end
		end
	end
	return planet_control_map
end

function orecrafter.BuildPlanetTileFluidMap()
	local planet_tile_fluid_map={}
	for planet_name,planet in pairs(data.raw.planet or {})do
		local settings=planet.map_gen_settings and planet.map_gen_settings.autoplace_settings
		local tiles=settings and settings.tile and settings.tile.settings
		if(tiles)then
			for tile_name in pairs(tiles)do
				local tile=data.raw.tile[tile_name]
				local fluid=tile and tile.fluid
				if(fluid)then
					planet_tile_fluid_map[fluid]=planet_tile_fluid_map[fluid] or {}
					planet_tile_fluid_map[fluid][planet_name]=true
				end
			end
		end
	end
	return planet_tile_fluid_map
end

function orecrafter.RemoveNaturalSources()
	if(not orecrafter.remove_natural_sources)then return end
	local rock_entities={}
	for _,pool in pairs({data.raw["simple-entity"],data.raw["simple-entity-with-owner"]})do
		for name,entity in pairs(pool or {})do
			if(entity.count_as_rock_for_filtered_deconstruction and entity.minable)then
				rock_entities[name]=true
			end
		end
	end
	local controls_to_remove={trees=true,rocks=true}
	for _,tree in pairs(data.raw.tree or {})do
		local control=tree.autoplace and tree.autoplace.control
		if(control)then controls_to_remove[control]=true end
	end
	for _,plant in pairs(data.raw.plant or {})do
		local control=plant.autoplace and plant.autoplace.control
		if(control)then controls_to_remove[control]=true end
	end
	for name in pairs(rock_entities)do
		local entity=(data.raw["simple-entity"] and data.raw["simple-entity"][name]) or (data.raw["simple-entity-with-owner"] and data.raw["simple-entity-with-owner"][name])
		local control=entity and entity.autoplace and entity.autoplace.control
		if(control)then controls_to_remove[control]=true end
	end
	for _,planet in pairs(data.raw.planet or {})do
		local map_settings=planet.map_gen_settings
		if(map_settings)then
			local controls=map_settings.autoplace_controls
			if(controls)then
				for control_name in pairs(controls_to_remove)do
					controls[control_name]=nil
				end
			end
			local entities=map_settings.autoplace_settings and map_settings.autoplace_settings.entity and map_settings.autoplace_settings.entity.settings
			if(entities)then
				for entity_name in pairs(entities)do
					if(data.raw.resource[entity_name] or data.raw.tree[entity_name] or data.raw.plant[entity_name] or rock_entities[entity_name])then
						entities[entity_name]=nil
					end
				end
			end
		end
	end
end

function orecrafter.PlanetListFor(map,key)
	local planets=map and map[key]
	if(not planets)then return nil end
	local list=SortedKeys(planets)
	return (#list>0 and list or nil)
end

function orecrafter.RegisterRecipe(recipe,output_key)
	orecrafter.temp[recipe.name]=recipe
	if(output_key and not orecrafter.recipes[output_key])then
		orecrafter.recipes[output_key]=recipe
	end
end

function orecrafter.ApplyPlanetConditions(planets,context)
	if(not orecrafter.restrict_planet_resources)then return nil end
	if(not planets or #planets==0)then
		error("OreCrafter: missing planet mapping for "..tostring(context)..". Fix the planet resource map or disable 'Restrict planet resources'.")
	end
	if(not orecrafter.planet_conditions)then
		error("OreCrafter: planet surface conditions unavailable for "..tostring(context)..".")
	end
	local filtered={}
	for _,planet_name in ipairs(planets)do
		local conditions=orecrafter.planet_conditions[planet_name]
		if(not conditions or #conditions==0)then
			error("OreCrafter: missing surface properties for planet '"..tostring(planet_name).."' required by "..tostring(context)..".")
		end
		table.insert(filtered,{planet=planet_name,conditions=conditions})
	end
	return filtered
end

function orecrafter.RegisterPlanetRecipes(base_recipe,output_key,planets)
	if(not orecrafter.restrict_planet_resources and (not planets or #planets==0))then
		local is_bootstrap=base_recipe.name:find("^orecrafter_bootstrap")~=nil
		orecrafter.AssignPlanetRecipeOrder(base_recipe,output_key,"global",is_bootstrap)
		orecrafter.RegisterRecipe(base_recipe,output_key)
		return
	end
	local entries={}
	if(orecrafter.restrict_planet_resources)then
		entries=orecrafter.ApplyPlanetConditions(planets,base_recipe.name) or {}
	else
		for _,planet_name in ipairs(planets)do
			table.insert(entries,{planet=planet_name,conditions=nil})
		end
	end
	for _,entry in ipairs(entries)do
		local dupe=table.deepcopy(base_recipe)
		dupe.name=base_recipe.name.."-"..entry.planet
		dupe.localised_name=orecrafter.PlanetRecipeName(base_recipe,entry.planet)
		if(entry.conditions)then dupe.surface_conditions=entry.conditions end
		dupe.enabled=false
		local is_bootstrap=dupe.name:find("^orecrafter_bootstrap")~=nil
		orecrafter.AssignPlanetRecipeOrder(dupe,output_key,entry.planet,is_bootstrap)
		orecrafter.RegisterRecipe(dupe,output_key)
	end
end

function orecrafter.OutputKey(rs)
	return (rs.type or "item")..":"..rs.name
end

function orecrafter.AddPlanetsForOutput(map,output_key,planets)
	if(not planets)then return end
	map[output_key]=map[output_key] or {}
	if(#planets>0)then
		for _,planet_name in ipairs(planets)do
			map[output_key][planet_name]=true
		end
	else
		for planet_name in pairs(planets)do
			map[output_key][planet_name]=true
		end
	end
end

function orecrafter.MakeRecipeBase(name,icons,icon_size,order,localised_name,allow_productivity)
	local dupe={
		name=name,
		enabled=true,
		type="recipe",
		icons=icons,
		icon_size=icon_size,
		allow_decomposition=false,
		order=order,
		localised_name=localised_name,
	}
	if(allow_productivity)then dupe.allow_productivity=true end
	return dupe
end

function orecrafter.ApplyItemDupe(dupe,item_name,subgroup)
	dupe.category="crafting"
	dupe.subgroup=subgroup
	dupe.energy_required=orecrafter.settings.item_speed
	local amt=orecrafter.settings.item_needed
	local amd=orecrafter.settings.item_count
	dupe.ingredients={{type="item",name=item_name,amount=amt}}
	dupe.results={{type="item",name=item_name,amount=amt+amd}}
end

function orecrafter.ApplyFluidDupe(dupe,fluid_name,temperature)
	dupe.category="oil-processing"
	dupe.subgroup="orecrafter-dupe-oil"
	dupe.order="z"
	dupe.energy_required=orecrafter.settings.fluid_speed
	local amt=orecrafter.settings.fluid_needed
	local amd=orecrafter.settings.fluid_count
	dupe.ingredients={{type="fluid",name=fluid_name,amount=amt}}
	local result={type="fluid",name=fluid_name,amount=amt+amd}
	if(temperature)then result.temperature=temperature end
	dupe.results={result}
end

orecrafter.planet_conditions=orecrafter.BuildPlanetConditions()
orecrafter.planet_resource_map=orecrafter.BuildPlanetResourceMap()
orecrafter.planet_entity_map=orecrafter.BuildPlanetEntityMap()
orecrafter.planet_control_map=orecrafter.BuildPlanetAutoplaceControlMap()
orecrafter.planet_tile_fluid_map=orecrafter.BuildPlanetTileFluidMap()
orecrafter.RemoveNaturalSources()
orecrafter.output_tech_depth=orecrafter.BuildOutputTechDepthMap()
function orecrafter.PlanetLabel(planet_name)
	local planet=data.raw.planet and data.raw.planet[planet_name]
	if(planet and planet.localised_name)then return planet.localised_name end
	local fallback={
		nauvis="Nauvis",
		vulcanus="Vulcanus",
		gleba="Gleba",
		fulgora="Fulgora",
		aquilo="Aquilo",
	}
	return fallback[planet_name] or planet_name
end

---Returns a stable ordering index for planets (based on prototype order then name).
function orecrafter.PlanetOrderIndexMap()
	if(orecrafter.planet_order_map)then return orecrafter.planet_order_map end
	local list={}
	for planet_name,planet in pairs(data.raw.planet or {})do
		local order=planet and planet.order or planet_name
		table.insert(list,{name=planet_name,order=tostring(order)})
	end
	table.sort(list,function(a,b)
		if(a.order==b.order)then return a.name<b.name end
		return a.order<b.order
	end)
	local map={}
	for index,entry in ipairs(list)do
		map[entry.name]=index
	end
	orecrafter.planet_order_map=map
	return map
end

function orecrafter.PlanetOrderIndex(planet_name)
	local map=orecrafter.PlanetOrderIndexMap()
	return map[planet_name] or 999
end

function orecrafter.PlanetLinePrefix(planet_name,is_fluid)
	local index=orecrafter.PlanetOrderIndex(planet_name)
	local type_key=is_fluid and "b" or "a"
	return string.format("%03d-%s",index,type_key)
end

function orecrafter.EnsurePlanetSubgroup(planet_name,is_fluid)
	local clean_name=planet_name or "global"
	local subgroup="orecrafter-dupe-planet-"..clean_name..(is_fluid and "-fluids" or "-items")
	if(data.raw["item-subgroup"][subgroup])then return subgroup end
	local order
	if(clean_name=="global")then
		order=is_fluid and "1" or "0"
	else
		order="b"..orecrafter.PlanetLinePrefix(clean_name,is_fluid)
	end
	data:extend{{
		type="item-subgroup",
		name=subgroup,
		group="orecrafter-duplications",
		order=order,
	}}
	return subgroup
end

function orecrafter.AssignPlanetRecipeOrder(recipe,output_key,planet_name,is_bootstrap,name_key_override)
	local output_type,output_name=output_key and output_key:match("^(.-):(.+)$") or nil,nil
	local is_fluid=(output_type=="fluid")
	local subgroup=orecrafter.EnsurePlanetSubgroup(planet_name,is_fluid)
	local prefix=orecrafter.PlanetLinePrefix(planet_name,is_fluid)
	local kind=is_bootstrap and "0" or "1"
	local name_key=name_key_override or output_name or recipe.name
	name_key=tostring(name_key):lower()
	recipe.subgroup=subgroup
	recipe.order=prefix.."-"..name_key.."-"..kind
end

function orecrafter.PlanetRecipeName(base_recipe,planet_name)
	local label=orecrafter.PlanetLabel(planet_name)
	local base_name=base_recipe.localised_name or {"recipe-name."..base_recipe.name}
	return {"", base_name, " (", label, ")"}
end

-- Returns the list of planets where an entity can naturally spawn based on map-gen controls and settings.
function orecrafter.PlanetsForEntity(entity)
	if(not entity)then return nil end
	local control=entity.autoplace and entity.autoplace.control
	if(entity.type=="tree")then
		local planets=orecrafter.planet_entity_map and orecrafter.PlanetListFor(orecrafter.planet_entity_map,entity.name)
		if(not planets and control and control~="trees")then
			planets=orecrafter.PlanetListFor(orecrafter.planet_control_map,control)
		end
		planets=planets or orecrafter.PlanetListFor(orecrafter.planet_control_map,entity.name)
		planets=planets or orecrafter.PlanetListFor(orecrafter.planet_control_map,entity.type)
		return planets
	end
	local planets=control and orecrafter.PlanetListFor(orecrafter.planet_control_map,control)
	planets=planets or orecrafter.PlanetListFor(orecrafter.planet_control_map,entity.name)
	planets=planets or orecrafter.PlanetListFor(orecrafter.planet_control_map,entity.type)
	planets=planets or (orecrafter.planet_entity_map and orecrafter.PlanetListFor(orecrafter.planet_entity_map,entity.name))
	return planets
end

function orecrafter.PlanetListMissing(planet_map,covered_map)
	if(not planet_map)then return nil end
	local list={}
	for planet_name in pairs(planet_map)do
		if(not (covered_map and covered_map[planet_name]))then
			table.insert(list,planet_name)
		end
	end
	table.sort(list)
	return (#list>0 and list or nil)
end

function orecrafter.ApplyFusionGeneratorSurfaceConditions()
	local generators=data.raw["electric-energy-interface"]
	local fusion=generators and generators["orecrafter-fusiongenerator"]
	if(not fusion)then return end
	fusion.surface_conditions=nil
end

orecrafter.ApplyFusionGeneratorSurfaceConditions()

function orecrafter.RecipeFromResource(e)
	if(not e.minable)then return end
	if(not proto.IsAutoplaceControl(e) and not (orecrafter.planet_resource_map and orecrafter.planet_resource_map[e.name]))then return end
	local rz=proto.Results(e.minable)
	if(not rz or not rz[1])then return end
	local primary=orecrafter.SelectPrimaryResult(rz,e.name)
	local rname=primary.name
	local cat=(primary.type=="fluid" and "basic-fluid" or (e.category or "basic-solid"))
	local temp=primary.temperature
	local function IconSizeFromProto(proto)
		if(proto.icon_size)then return proto.icon_size end
		if(proto.icons and proto.icons[1] and proto.icons[1].icon_size)then return proto.icons[1].icon_size end
		return 64
	end
	local icon_source=e
	local localised_name=e.localised_name or {"entity-name."..e.name}
	if(cat=="basic-fluid")then
		local fluid=data.raw.fluid[rname]
		if(fluid)then
			icon_source=fluid
			localised_name=fluid.localised_name or {"fluid-name."..rname}
		end
	end

	local dupe=orecrafter.MakeRecipeBase(
		"orecrafter-dupe-"..e.name,
		icon_source.icons or {{icon=icon_source.icon}},
		IconSizeFromProto(icon_source),
		(e.order and "a3"..e.order or "a3"),
		localised_name
	)

	if(cat=="basic-fluid")then
		orecrafter.ApplyFluidDupe(dupe,rname,temp)
	else
		orecrafter.ApplyItemDupe(dupe,rname,"orecrafter-dupe-raw")
	end

	if(e.minable.required_fluid)then
		dupe.category="chemistry"
		dupe.subgroup="orecrafter-dupe-chem"
		table.insert(dupe.ingredients,{type="fluid",name=e.minable.required_fluid,amount=e.minable.fluid_amount})
		orecrafter.resources.chem[rname]=e
	elseif(cat~="basic-fluid")then
		orecrafter.resources.raw[rname]=e
	elseif(dupe.subgroup=="orecrafter-dupe-oil")then
		orecrafter.resources.oil[rname]=e
	end
	local output_key=orecrafter.OutputKey(dupe.results[1])
	local planets=orecrafter.PlanetListFor(orecrafter.planet_resource_map,e.name)
	orecrafter.RegisterPlanetRecipes(dupe,output_key,planets)
end

function orecrafter.RecipeFromTree(e,rsid)
	if(not e.minable)then return end
	local planets=orecrafter.PlanetsForEntity(e)
	if(not planets and not proto.IsAutoplaceControl(e))then return end
	if(not planets and orecrafter.restrict_planet_resources)then return end
	local min=proto.Results(e.minable)
	if(not rsid)then
		for i,x in pairs(min)do
			orecrafter.RecipeFromTree(e,i)
		end
		return
	end
	local rz=proto.Result(min[rsid]) if(rz.type=="fluid")then return end
	local rname=rz.name
	local output_key=orecrafter.OutputKey({type="item",name=rname})
	if(not rname or orecrafter.recipes[output_key])then return end
	local raw=proto.RawItem(rname)
	if(not raw)then error("A tree possibly giving a fluid? How?: " .. serpent.block(e)) end

	local dupe=orecrafter.MakeRecipeBase(
		"orecrafter-dupe-"..rname,
		proto.Icons(raw),
		raw.icon_size,
		(raw.order and "a3"..raw.order..rsid or "a3"..rsid),
		raw.localised_name or {"item-name."..rname}
	)

	orecrafter.ApplyItemDupe(dupe,rname,"orecrafter-dupe-tree")
	orecrafter.RegisterPlanetRecipes(dupe,output_key,planets)
	orecrafter.resources.tree[rname]=e
end

function orecrafter.RecipeFromPlant(e,rsid)
	if(not e.minable or not proto.IsAutoplaceControl(e))then return end
	local min=proto.Results(e.minable)
	if(not rsid)then
		for i in pairs(min)do
			orecrafter.RecipeFromPlant(e,i)
		end
		return
	end
	local rz=proto.Result(min[rsid]) if(rz.type=="fluid")then return end
	local rname=rz.name
	if(not rname or not orecrafter.plant_outputs[rname])then return end
	local output_key=orecrafter.OutputKey({type="item",name=rname})
	if(orecrafter.recipes[output_key])then return end
	local raw=proto.RawItem(rname)
	if(not raw)then return end

	local dupe=orecrafter.MakeRecipeBase(
		"orecrafter-dupe-"..rname,
		proto.Icons(raw),
		raw.icon_size,
		(raw.order and "a3"..raw.order..rsid or "a3"..rsid),
		raw.localised_name or {"item-name."..rname},
		true
	)

	orecrafter.ApplyItemDupe(dupe,rname,"orecrafter-dupe-organic")
	dupe.category="organic"
	local control=e.autoplace and e.autoplace.control
	local planets=control and orecrafter.PlanetListFor(orecrafter.planet_control_map,control)
	orecrafter.RegisterPlanetRecipes(dupe,output_key,planets)
end

function orecrafter.RecipeFromTileFluid(fluid_name)
	if(fluid_name=="water" and not orecrafter.allow_water_duplication)then return end
	local fluid=data.raw.fluid[fluid_name]
	if(not fluid)then return end
	local output_key=orecrafter.OutputKey({type="fluid",name=fluid_name})
	if(orecrafter.recipes[output_key])then return end
	local dupe=orecrafter.MakeRecipeBase(
		"orecrafter-dupe-"..fluid_name,
		fluid.icons or {{icon=fluid.icon}},
		fluid.icon_size,
		"z",
		fluid.localised_name or {"fluid-name."..fluid_name}
	)
	orecrafter.ApplyFluidDupe(dupe,fluid_name)
	local planets=orecrafter.PlanetListFor(orecrafter.planet_tile_fluid_map,fluid_name)
	orecrafter.RegisterPlanetRecipes(dupe,output_key,planets)
end

function orecrafter.BuildOutputPlanetMap()
	local output_planet_map={}
	for resource_name,planets in pairs(orecrafter.planet_resource_map or {})do
		local res=data.raw.resource[resource_name]
		if(res and res.minable)then
			local rz=proto.Results(res.minable)
			if(rz and rz[1])then
				local primary=orecrafter.SelectPrimaryResult(rz,res.name)
				local key=orecrafter.OutputKey(primary)
				orecrafter.AddPlanetsForOutput(output_planet_map,key,planets)
			end
		end
	end
	for plant_name,plant in pairs(data.raw.plant or {})do
		local planets=orecrafter.PlanetsForEntity(plant)
		local minable=plant.minable
		if(planets and minable)then
			local rz=proto.Results(minable)
			for _,rx in pairs(rz or {})do
				local result=proto.Result(rx)
				if(result and result.type=="item" and orecrafter.plant_outputs[result.name])then
					local key=orecrafter.OutputKey(result)
					orecrafter.AddPlanetsForOutput(output_planet_map,key,planets)
				end
			end
		end
	end
	for tree_name,tree in pairs(data.raw.tree or {})do
		local planets=orecrafter.PlanetsForEntity(tree)
		local minable=tree.minable
		if(planets and minable)then
			local rz=proto.Results(minable)
			for _,rx in pairs(rz or {})do
				local result=proto.Result(rx)
				if(result and result.type=="item")then
					local key=orecrafter.OutputKey(result)
					orecrafter.AddPlanetsForOutput(output_planet_map,key,planets)
				end
			end
		end
	end
	for fluid_name,planets in pairs(orecrafter.planet_tile_fluid_map or {})do
		if(fluid_name=="water" and not orecrafter.allow_water_duplication)then
			-- Skip water if the option is disabled.
		else
			local key=orecrafter.OutputKey({type="fluid",name=fluid_name})
			orecrafter.AddPlanetsForOutput(output_planet_map,key,planets)
		end
	end
	return output_planet_map
end

function orecrafter.OutputsForPlanet(output_planet_map,planet_name)
	local outputs={}
	for key,planets in pairs(output_planet_map or {})do
		if(planets[planet_name])then outputs[key]=true end
	end
	return outputs
end

function orecrafter.AddRecipeUnlock(tech_name,recipe_name)
	if(not tech_name or not recipe_name)then return end
	local tech=data.raw.technology[tech_name]
	if(not tech)then return end
	tech.effects=tech.effects or {}
	for _,effect in pairs(tech.effects)do
		if(effect.type=="unlock-recipe" and effect.recipe==recipe_name)then return end
	end
	table.insert(tech.effects,{type="unlock-recipe",recipe=recipe_name})
end

--[[ Scan for resources and trees ]]--

function orecrafter.ScanResources()
	for k,v in pairs(data.raw.resource)do orecrafter.RecipeFromResource(v) end
	orecrafter.Extend()
end
function orecrafter.ScanTrees()
	for k,v in pairs(data.raw.tree)do orecrafter.RecipeFromTree(v) end
	orecrafter.Extend()
end
function orecrafter.ScanPlants()
	for k,v in pairs(data.raw.plant or {})do orecrafter.RecipeFromPlant(v) end
	orecrafter.Extend()
end
function orecrafter.ScanTileFluids()
	for fluid_name in pairs(orecrafter.planet_tile_fluid_map or {})do
		orecrafter.RecipeFromTileFluid(fluid_name)
	end
	orecrafter.Extend()
end

function orecrafter.RegisterRockOutputs(entity)
	if(not entity or not entity.minable or not entity.count_as_rock_for_filtered_deconstruction)then return end
	local results=proto.Results(entity.minable)
	if(not results)then return end
	local planets=orecrafter.planet_entity_map and orecrafter.planet_entity_map[entity.name]
	if(not planets or table_size(planets)==0)then return end
	for _,rx in pairs(results)do
		local result=proto.Result(rx)
		if(result and result.type~="fluid")then
			local output_key=orecrafter.OutputKey(result)
			orecrafter.rock_outputs[output_key]=orecrafter.rock_outputs[output_key] or result
			orecrafter.rock_output_planet_map[output_key]=orecrafter.rock_output_planet_map[output_key] or {}
			if(planets)then
				for planet_name in pairs(planets)do
					orecrafter.rock_output_planet_map[output_key][planet_name]=true
				end
			end
		end
	end
end

function orecrafter.MakeRockRecipes()
	local output_planet_map=orecrafter.output_planet_map or {}
	for output_key,planet_map in pairs(orecrafter.rock_output_planet_map or {})do
		if(orecrafter.restrict_planet_resources)then
			local missing=orecrafter.PlanetListMissing(planet_map,output_planet_map[output_key])
			if(missing)then
				local result=orecrafter.rock_outputs[output_key]
				local raw=result and proto.RawItem(result.name)
				if(raw)then
					local dupe=orecrafter.MakeRecipeBase(
						"orecrafter-dupe-rock-"..result.name,
						proto.Icons(raw),
						raw.icon_size,
						(raw.order and "a3"..raw.order or "a3"),
						raw.localised_name or {"item-name."..result.name}
					)
					orecrafter.ApplyItemDupe(dupe,result.name,"orecrafter-dupe-raw")
					orecrafter.RegisterPlanetRecipes(dupe,output_key,missing)
				end
			end
		elseif(not orecrafter.recipes[output_key])then
			local result=orecrafter.rock_outputs[output_key]
			local raw=result and proto.RawItem(result.name)
			if(raw)then
				local dupe=orecrafter.MakeRecipeBase(
					"orecrafter-dupe-rock-"..result.name,
					proto.Icons(raw),
					raw.icon_size,
					(raw.order and "a3"..raw.order or "a3"),
					raw.localised_name or {"item-name."..result.name}
				)
				orecrafter.ApplyItemDupe(dupe,result.name,"orecrafter-dupe-raw")
				orecrafter.RegisterPlanetRecipes(dupe,output_key,orecrafter.PlanetListMissing(planet_map,output_planet_map[output_key]))
			end
		end
		orecrafter.AddPlanetsForOutput(output_planet_map,output_key,planet_map)
	end
	orecrafter.output_planet_map=output_planet_map
end

function orecrafter.ScanRocks()
	orecrafter.rock_output_planet_map={}
	orecrafter.rock_outputs={}
	for _,pool in pairs({data.raw["simple-entity"],data.raw["simple-entity-with-owner"]})do
		for _,entity in pairs(pool or {})do
			orecrafter.RegisterRockOutputs(entity)
		end
	end
	orecrafter.MakeRockRecipes()
	orecrafter.Extend()
end
orecrafter.ScanResources()
orecrafter.ScanTrees()
orecrafter.ScanPlants()
orecrafter.ScanTileFluids()
orecrafter.output_planet_map=orecrafter.BuildOutputPlanetMap()
orecrafter.ScanRocks()


--[[ Make the Bootstrap Recipe ]]--
function orecrafter.MakeBootstrapRecipes()
	local output_planet_map=orecrafter.output_planet_map or orecrafter.BuildOutputPlanetMap()
	local orecrafterBootstrapChance=0.05
	local orecrafterBootstrapAmount=orecrafter.settings.item_count

	for planet_name in pairs(data.raw.planet or {})do
		local outputs=orecrafter.OutputsForPlanet(output_planet_map,planet_name)
		if(next(outputs)~=nil)then
			local recipe_name=(planet_name=="nauvis") and "orecrafter_bootstrap" or "orecrafter_bootstrap-"..planet_name
			local r={
				name=recipe_name,
				type="recipe",
				icon_size=32,
				icon=modname.."/graphics/icons/bootstrap.png",
				order="a1aaa",
				category="crafting",
				subgroup="orecrafter-dupe-bootstrap",
				energy_required=5,
				ingredients={},
				results={},
				enabled=(planet_name=="nauvis"),
			}
		if(planet_name~="nauvis")then
			local label=orecrafter.PlanetLabel(planet_name)
			r.localised_name={"", {"recipe-name.orecrafter_bootstrap"}, " (", label, ")"}
		end
			if(orecrafter.restrict_planet_resources)then
				local conditions=orecrafter.planet_conditions[planet_name]
				if(conditions and #conditions>0)then
					r.surface_conditions=conditions
				end
			end
			orecrafter.AssignPlanetRecipeOrder(r,nil,"global",true,r.name)

			for _,output_key in ipairs(SortedKeys(outputs))do
				local v=orecrafter.recipes[output_key]
				if(v and v.results and v.results[1])then
					local g
					local vname=v.results[1].name
					if(v.results[1].type=="item")then
						g={
							type="item",
							name=vname,
							probability=orecrafterBootstrapChance,
							amount=math.max(math.ceil(orecrafterBootstrapAmount)*2,1),
						}
					end
					if(g)then table.insert(r.results,g) end
				end
			end

		if(#r.results>0)then
			data:extend{r}
		end
		end
	end
end
orecrafter.MakeBootstrapRecipes()

--[[ Make the Bootstrap Fluid Recipes ]]--
function orecrafter.MakeBootstrapFluidRecipes()
	local output_planet_map=orecrafter.output_planet_map or orecrafter.BuildOutputPlanetMap()
	local bootstrap_amount=math.max(math.ceil(orecrafter.settings.fluid_count*0.05),1)
	local bootstrap_time=orecrafter.settings.fluid_speed

	local function IconLayers(proto)
		if(proto.icons)then return table.deepcopy(proto.icons) end
		if(proto.icon)then return {{icon=proto.icon,icon_size=proto.icon_size,icon_mipmaps=proto.icon_mipmaps}} end
		return {}
	end

	for planet_name in pairs(data.raw.planet or {})do
		local outputs=orecrafter.OutputsForPlanet(output_planet_map,planet_name)
		if(next(outputs)~=nil)then
			for output_key in pairs(outputs)do
				local output_type,output_name=output_key:match("^(.-):(.+)$")
				if(output_type=="fluid")then
					local fluid=data.raw.fluid[output_name]
					if(fluid)then
						local recipe_name="orecrafter_bootstrap-fluid-"..planet_name.."-"..output_name
						if(not data.raw.recipe[recipe_name])then
							local r={
								name=recipe_name,
								type="recipe",
								icons=IconLayers(fluid),
								icon_size=fluid.icon_size or (fluid.icons and fluid.icons[1] and fluid.icons[1].icon_size) or 64,
								order="a1aafluid-"..output_name,
								category="crafting-with-fluid",
								subgroup="orecrafter-dupe-bootstrap",
								energy_required=bootstrap_time,
								ingredients={},
								results={},
								enabled=(planet_name=="nauvis"),
							}
							local result={type="fluid",name=output_name,amount=bootstrap_amount}
							if(fluid.default_temperature)then result.temperature=fluid.default_temperature end
							r.results={result}
							if(planet_name~="nauvis")then
								local label=orecrafter.PlanetLabel(planet_name)
								r.localised_name={"", {"fluid-name."..output_name}, " ", {"recipe-name.orecrafter_bootstrap"}, " (", label, ")"}
							else
								r.localised_name={"", {"fluid-name."..output_name}, " ", {"recipe-name.orecrafter_bootstrap"}}
							end
							if(orecrafter.restrict_planet_resources)then
								local conditions=orecrafter.planet_conditions[planet_name]
								if(conditions and #conditions>0)then
									r.surface_conditions=conditions
								end
							end
							orecrafter.AssignPlanetRecipeOrder(r,"fluid:"..output_name,planet_name,true,output_name)
							data:extend{r}
						end
					end
				end
			end
		end
	end
end
orecrafter.MakeBootstrapFluidRecipes()

--- Resolves a minable entity prototype by name across known entity pools.
function orecrafter.ResolveMinableEntity(entity_name)
	if(not entity_name)then return nil end
	for _,pool in pairs({data.raw.resource,data.raw.tree,data.raw.plant,data.raw["simple-entity"],data.raw["simple-entity-with-owner"]})do
		local entity=pool and pool[entity_name]
		if(entity)then return entity end
	end
	return nil
end

--- Collects unique item outputs from a minable entity definition.
function orecrafter.CollectMinableItemResults(entity)
	if(not entity or not entity.minable)then return nil end
	local results=proto.Results(entity.minable)
	if(not results)then return nil end
	local list={}
	local seen={}
	for _,rx in pairs(results)do
		local result=proto.Result(rx)
		if(result and result.name and (result.type==nil or result.type=="item"))then
			if(not seen[result.name])then
				seen[result.name]=true
				table.insert(list,{type="item",name=result.name})
			end
		end
	end
	return (#list>0 and list or nil)
end

--- Orders minable outputs by planet restriction (fewest planets) then tech depth (highest first).
function orecrafter.OrderMineTriggerOutputs(results,entity_planets)
	local ranked={}
	for _,result in ipairs(results or {})do
		local output_key=orecrafter.OutputKey(result)
		local planet_map=orecrafter.output_planet_map and orecrafter.output_planet_map[output_key]
		local planet_count
		if(planet_map)then
			planet_count=table_size(planet_map)
		elseif(entity_planets)then
			planet_count=table_size(entity_planets)
		else
			planet_count=999999
		end
		table.insert(ranked,{result=result,depth=orecrafter.OutputTechDepth(result),planet_count=planet_count})
	end
	table.sort(ranked,function(a,b)
		if(a.planet_count~=b.planet_count)then return a.planet_count<b.planet_count end
		if(a.depth==b.depth)then return a.result.name<b.result.name end
		return a.depth>b.depth
	end)
	return ranked
end

--- Converts mine-entity research triggers to craft-item triggers using minable outputs.
function orecrafter.ConvertMineEntityTriggers()
	for tech_name,tech in pairs(data.raw.technology or {})do
		local trigger=tech.research_trigger
		if(trigger and trigger.type=="mine-entity" and trigger.entity)then
			local entity=orecrafter.ResolveMinableEntity(trigger.entity)
			if(not entity)then
				log("OreCrafter: mine-entity trigger for '"..tech_name.."' references unknown entity '"..trigger.entity.."'. Leaving unchanged.")
			else
				local results=orecrafter.CollectMinableItemResults(entity)
				if(not results)then
					log("OreCrafter: mine-entity trigger for '"..tech_name.."' has no item outputs on '"..trigger.entity.."'. Leaving unchanged.")
				else
					local entity_planets=orecrafter.planet_entity_map and orecrafter.planet_entity_map[entity.name]
					local ranked=orecrafter.OrderMineTriggerOutputs(results,entity_planets)
					local primary=ranked[1] and ranked[1].result
					if(primary and primary.name)then
						tech.research_trigger={type="craft-item",item=primary.name,count=1}
					end
				end
			end
		end
	end
end

orecrafter.ConvertMineEntityTriggers()

--[[ Now add the procedurally generated orecrafter.basics recipes to the technology that unlocked it ? ]]--

orecrafter.starters={} -- the starting recipes that can be mined by hand (iron-ore)
function logic.HandChanged()

end
