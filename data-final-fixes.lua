lib={DATA_LOGIC=true}
require("lib/lib")

local hand=logic.hand
local orecrafter={}
local modname="__orecrafter__"

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

function orecrafter.RecipeFromResource(e)
	if(not proto.IsAutoplaceControl(e) or not e.minable)then return end
	local rz=proto.Results(e.minable)
	if(not rz or not rz[1])then return end
	local rname=proto.Result(rz[1]).name
	local isfluid=false
	local cat=e.category or "basic-solid"
	local temp
	for k,v in pairs(rz)do
		if(v.type=="fluid") then
			cat="basic-fluid"
			temp=v.temperature
			break
		end
	end

	local dupe={
		name="orecrafter-dupe-"..e.name,
		enabled=true,
		type="recipe",
		icons=e.icons or {{icon=e.icon}},
		icon_size=e.icon_size,
		allow_decomposition=false,
		order=(e.order and "a3"..e.order or "a3"),
		localised_name=e.localised_name or {"entity-name."..e.name},
	}

	if(cat=="basic-fluid")then
		dupe.category="oil-processing"
		dupe.subgroup="orecrafter-dupe-oil"
		dupe.order="z"
		dupe.energy_required=settings.startup["orecrafter_fluid_speed"].value
		local amt=settings.startup["orecrafter_fluid_needed"].value
		local amd=settings.startup["orecrafter_fluid_count"].value
		dupe.ingredients={{type="fluid",name=rname,amount=amt}}
		dupe.results={{type="fluid",name=rname,amount=amt+amd,temperature=temp}}
	else
		dupe.category="crafting"
		dupe.subgroup="orecrafter-dupe-raw"
		dupe.energy_required=settings.startup["orecrafter_item_speed"].value
		local amt=settings.startup["orecrafter_item_needed"].value
		local amd=settings.startup["orecrafter_item_count"].value
		dupe.ingredients={{type="item",name=rname,amount=amt}}
		dupe.results={{type="item",name=rname,amount=amt+amd}}
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
	orecrafter.recipes[e.name]=dupe
	orecrafter.temp[e.name]=dupe
end

function orecrafter.RecipeFromTree(e,rsid)
	if(not e.minable or not proto.IsAutoplaceControl(e))then return end
	local min=proto.Results(e.minable)
	if(not rsid)then
		for i,x in pairs(min)do
			orecrafter.RecipeFromTree(e,i)
		end
		return
	end
	local rz=proto.Result(min[rsid]) if(rz.type=="fluid")then return end
	local rname=rz.name
	if(not rname or orecrafter.recipes[rname])then return end
	local raw=proto.RawItem(rname)
	if(not raw)then error("A tree possibly giving a fluid? How?: " .. serpent.block(e)) end

	local dupe={
		name="orecrafter-dupe-"..rname,
		enabled=true,
		type="recipe",
		icons=proto.Icons(raw),
		allow_decomposition=false,
		order=(raw.order and "a3"..raw.order..rsid or "a3"..rsid),
		localised_name=raw.localised_name or {"item-name."..rname},
	}

	dupe.category="crafting"
	dupe.subgroup="orecrafter-dupe-tree"
	dupe.energy_required=settings.startup["orecrafter_item_speed"].value
	local amt=settings.startup["orecrafter_item_needed"].value
	local amd=settings.startup["orecrafter_item_count"].value
	dupe.ingredients={{type="item",name=rname,amount=amt}}
	dupe.results={{type="item",name=rname,amount=amt+amd}}
	orecrafter.recipes[rname]=dupe
	orecrafter.temp[rname]=dupe
	orecrafter.resources.tree[rname]=e
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
orecrafter.ScanResources()
orecrafter.ScanTrees()


--[[ Make the Bootstrap Recipe ]]--
function orecrafter.MakeBootstrapRecipe()

	local r={
		name="orecrafter_bootstrap",
		type="recipe",
		icon_size=32,
		icon=modname.."/graphics/icons/bootstrap.png",
		order="a1aaa",
		category="crafting",
		subgroup="orecrafter-dupe-bootstrap",
		energy_required=5,
		ingredients={},
		results={},
		enabled=true,
	}

	local orecrafterBootstrapChance = 0.05
	local orecrafterBootstrapAmount = settings.startup["orecrafter_item_count"].value

	for k,v in pairs(orecrafter.recipes)do
		local g={} local vname=v.results[1].name
		if(v.results[1].type=="item")then
			g.type="item"
			g.name=vname
			g.probability=orecrafterBootstrapChance
			g.amount=math.max(math.ceil(orecrafterBootstrapAmount)*2,1)
		elseif(proto.RawItem(vname.."-barrel"))then
			g.type="item"
			g.name=vname .. "-barrel"
			g.probability=orecrafterBootstrapChance
			g.amount=math.ceil(orecrafterBootstrapAmount)
		end
		table.insert(r.results,g)

	end
	data:extend{r}
	return r
end
orecrafter.MakeBootstrapRecipe()

--[[ Now add the procedurally generated orecrafter.basics recipes to the technology that unlocked it ? ]]--

orecrafter.starters={} -- the starting recipes that can be mined by hand (iron-ore)
function logic.HandChanged()

end
