
data:extend(
{

	{type="double-setting",name="orecrafter_item_speed",order="22a",
	setting_type="startup",default_value=5,
	minimum_value=1,maximum_value=60},

	{type="int-setting",name="orecrafter_item_needed",order="22b",
	setting_type="startup",default_value=5,
	minimum_value=1,maximum_value=100},

	{type="int-setting",name="orecrafter_item_count",order="22c",
	setting_type="startup",default_value=1,
	minimum_value=1,maximum_value=100},

	{type="double-setting",name="orecrafter_fluid_speed",order="23a",
	setting_type="startup",default_value=5,
	minimum_value=1,maximum_value=50},

	{type="int-setting",name="orecrafter_fluid_needed",order="23b",
	setting_type="startup",default_value=125,
	minimum_value=1,maximum_value=1000},

	{type="int-setting",name="orecrafter_fluid_count",order="23c",
	setting_type="startup",default_value=40,
	minimum_value=1,maximum_value=1000},

	{type="bool-setting",name="orecrafter_allow_water_duplication",order="23d",
	setting_type="startup",default_value=true},

	{type="bool-setting",name="orecrafter_restrict_planet_resources",order="23e",
	setting_type="startup",default_value=true},

	{type="bool-setting",name="orecrafter_remove_natural_sources",order="23f",
	setting_type="startup",default_value=true},

	{type="bool-setting",name="orecrafter_fusiongenerator_craftable",order="24a",
	setting_type="startup",default_value=false},

	{type="bool-setting",name="orecrafter_fusiongenerator_anywhere",order="24b",
	setting_type="startup",default_value=false},

	{type="int-setting",name="orecrafter_fusiongenerator_power",order="24c",
	setting_type="startup",default_value=1000,
	minimum_value=100,maximum_value=100000},

})
