local modname="__orecrafter__"

data:extend{ -- Crafting menu categories
	{
		name="orecrafter-duplications",type="item-group",order="q",order_in_recipe="0",enabled=true,
		icons={{icon=modname.."/graphics/icons/blackhole.png",icon_size=128}},
	},
	{name="orecrafter-dupe-bootstrap",type="item-subgroup",group="orecrafter-duplications",order="7"},
	{name="orecrafter-dupe-tree",type="item-subgroup",group="orecrafter-duplications",order="a"},
	{name="orecrafter-dupe-raw",type="item-subgroup",group="orecrafter-duplications",order="b"},
	{name="orecrafter-dupe-oil",type="item-subgroup",group="orecrafter-duplications",order="c"},
	{name="orecrafter-dupe-chem",type="item-subgroup",group="orecrafter-duplications",order="d"},
}

-- Infinite energy source to start the game
require "data/fusiongenerator"
