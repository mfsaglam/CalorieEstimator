# CalorieEstimator database evaluation

Generated: 2026-09-26T18:42:02.323144+00:00  
Scope: bundled offline database and fixed evaluation benchmark. No recipe rows, aliases, prompts, or runtime behavior were changed.

## Executive summary

- Database: 2,794 recipes, 1,233 ingredients, 3,392 recipe aliases, 11 ingredient aliases.
- Tiers: Tier A 2,716, Tier B 78.
- Median recipe composition: 4.0 ingredients; p10/p50/p90 = 2.0/4.0/9.0.
- Median energy density: 166.4 kcal/100g; p5/p50/p95 = 54.6/166.4/329.8.
- Fixed benchmark: 45 base + 14 modifier = 59 cases across 12 languages.
- Live cases executed: 45 of 59; successful: 40; exact FoundationModels requests: 17.
- Trusted RecipeID hit rate: 70.37%; failures/timeouts/safety refusals: 8.47%; batch-terminated before execution: 23.73%; mass conservation: 100.00%.

## Database statistics

### Provenance and quality tiers

| Source | Recipes |
|---|---:|
| USDA FoodData Central FNDDS | 2,778 |
| CalorieEstimator manually curated seed | 16 |

| Tier | Recipes |
|---|---:|
| A | 2,716 |
| B | 78 |

### Recipes by cuisine

| Cuisine | Recipes |
|---|---:|
| (unspecified) | 2,427 |
| Italian | 115 |
| Mexican | 86 |
| Puerto Rican | 55 |
| Chinese | 27 |
| Japanese | 21 |
| American | 9 |
| Spanish | 8 |
| Indian | 7 |
| Eastern Mediterranean | 6 |
| Latin American | 6 |
| Middle Eastern | 5 |
| Thai | 5 |
| Korean | 3 |
| Vietnamese | 3 |
| British / Irish | 1 |
| Dominican | 1 |
| Eastern European | 1 |
| French | 1 |
| German | 1 |
| Greek | 1 |
| Nordic | 1 |
| North African | 1 |
| Russian | 1 |
| Salvadoran | 1 |
| Turkish | 1 |

### Recipes by region

| Region | Recipes |
|---|---:|
| (unspecified) | 2,447 |
| Italy | 114 |
| Mexico | 86 |
| Puerto Rico | 55 |
| China | 27 |
| Japan | 21 |
| United States | 9 |
| India | 7 |
| Spain | 7 |
| Thailand | 5 |
| Korea | 3 |
| Vietnam | 3 |
| Dominican Republic | 1 |
| Eastern Europe | 1 |
| El Salvador | 1 |
| Germany | 1 |
| Greece | 1 |
| Lazio | 1 |
| Provence | 1 |
| Sweden | 1 |
| Turkey | 1 |
| Valencia | 1 |

### Ingredients per recipe

| Bucket | Recipes |
|---|---:|
| 1 | 0 |
| 2-3 | 1,116 |
| 4-5 | 784 |
| 6-10 | 734 |
| 11-15 | 144 |
| 16-25 | 16 |
| >25 | 0 |

### Default serving grams

| Bucket | Recipes |
|---|---:|
| 1-30 | 306 |
| 31-100 | 584 |
| 101-200 | 974 |
| 201-350 | 908 |
| 351-500 | 13 |
| >500 | 9 |

### kcal per 100g

| Bucket | Recipes |
|---|---:|
| <25 | 18 |
| 25-74 | 218 |
| 75-149 | 964 |
| 150-249 | 1,049 |
| 250-399 | 510 |
| 400-699 | 35 |
| >=700 | 0 |

## Suspicious-record screen

These are deterministic review flags, not deletion recommendations.

| Signal | Count |
|---|---:|
| fewer than 2 ingredients | 0 |
| more than 25 ingredients | 0 |
| low kcal | 1 |
| high kcal | 0 |
| dominated | 313 |
| survey description names | 818 |
| near duplicate groups | 203 |
| high similarity pairs | 621 |

### Ten most suspicious imported recipes

| Recipe | Classification | Signals | kcal/100g | Ingredients |
|---|---|---|---:|---:|
| `global.beets_canned_cooked_fat_added.fndds_75208023` — Beets, canned, cooked, fat added | clearly suspicious | single ingredient exceeds 95%, survey-specific name, serving-size extreme | 53.1 | 2 |
| `global.beets_fresh_cooked_fat_added.fndds_75208021` — Beets, fresh, cooked, fat added | clearly suspicious | single ingredient exceeds 95%, survey-specific name, serving-size extreme | 64.5 | 3 |
| `global.beets_fresh_cooked_no_added_fat.fndds_75208011` — Beets, fresh, cooked, no added fat | clearly suspicious | single ingredient exceeds 95%, survey-specific name, serving-size extreme | 42.9 | 2 |
| `global.okra_fresh_cooked_fat_added.fndds_75220021` — Okra, fresh, cooked, fat added | clearly suspicious | single ingredient exceeds 95%, survey-specific name, serving-size extreme | 54.9 | 3 |
| `global.summer_squash_yellow_or_green_canned_cooked_fat_added_ns.fndds_75233023` — Summer squash, yellow or green, canned, cooked, fat added, NS as to fat type | clearly suspicious | single ingredient exceeds 95%, survey-specific name, serving-size extreme | 35.3 | 3 |
| `global.asparagus_canned_cooked_fat_added_ns_as_to_fat_type.fndds_75202023` — Asparagus, canned, cooked, fat added, NS as to fat type | clearly suspicious | single ingredient exceeds 95%, survey-specific name | 41.4 | 2 |
| `global.asparagus_fresh_cooked_fat_added_ns_as_to_fat_type.fndds_75202021` — Asparagus, fresh, cooked, fat added, NS as to fat type | clearly suspicious | single ingredient exceeds 95%, survey-specific name | 42.3 | 3 |
| `global.asparagus_fresh_cooked_no_added_fat.fndds_75202011` — Asparagus, fresh, cooked, no added fat | clearly suspicious | single ingredient exceeds 95%, survey-specific name | 19.9 | 2 |
| `global.asparagus_frozen_cooked_fat_added_ns_as_to_fat_type.fndds_75202022` — Asparagus, frozen, cooked, fat added, NS as to fat type | clearly suspicious | single ingredient exceeds 95%, survey-specific name | 40.3 | 3 |
| `global.asparagus_frozen_cooked_no_added_fat.fndds_75202012` — Asparagus, frozen, cooked, no added fat | clearly suspicious | single ingredient exceeds 95%, survey-specific name | 17.9 | 2 |

## USDA/FNDDS canonical-dish quality

Heuristic classification from canonical names and ingredient counts only; no FoundationModels call. Stable 120-record category-stratified sample. Subjective labels should be reviewed manually before any deletion.

Sample size: **120**.

| Heuristic class | Sample count | Population count |
|---|---:|---:|
| canonical dish | 10 | 161 |
| useful prepared-food variant | 81 | 1603 |
| survey-specific / overly specific | 27 | 818 |
| questionable | 2 | 196 |

Representative **canonical dish** examples:
- Almond chicken (`global.almond_chicken.fndds_27445250`) — concise dish identity
- Bacon biscuit sandwich (`global.bacon_biscuit_sandwich.fndds_34002110`) — concise dish identity
- Banana pudding (`global.banana_pudding.fndds_13241000`) — concise dish identity
- Barbecue chicken (`global.barbecue_chicken.fndds_27146011`) — concise dish identity
- Barbecue rib sandwich (`global.barbecue_rib_sandwich.fndds_27520500`) — concise dish identity

Representative **useful prepared-food variant** examples:
- Adobo, with noodles (`global.adobo_with_noodles.fndds_58137300`) — specific but reusable prepared-food variant
- Adobo, with rice (`global.adobo_with_rice.fndds_58150530`) — specific but reusable prepared-food variant
- Alfredo sauce with added vegetables (`global.alfredo_sauce_with_added_vegetables.fndds_14650165`) — specific but reusable prepared-food variant
- Alfredo sauce with meat (`global.alfredo_sauce_with_meat.fndds_14650170`) — specific but reusable prepared-food variant
- Alfredo sauce with meat and added vegetables (`global.alfredo_sauce_with_meat_and_added_vegetables.fndds_14650175`) — specific but reusable prepared-food variant

Representative **survey-specific / overly specific** examples:
- Asian stir fry vegetables, cooked, fat added (`global.asian_stir_fry_vegetables_cooked_fat_added.fndds_75340020`) — contains FNDDS survey/preparation qualifier
- Asian stir fry vegetables, cooked, no added fat (`global.asian_stir_fry_vegetables_cooked_no_added_fat.fndds_75340010`) — contains FNDDS survey/preparation qualifier
- Asparagus, canned, cooked, fat added, NS as to fat type (`global.asparagus_canned_cooked_fat_added_ns_as_to_fat_type.fndds_75202023`) — contains FNDDS survey/preparation qualifier
- Asparagus, fresh, cooked, fat added, NS as to fat type (`global.asparagus_fresh_cooked_fat_added_ns_as_to_fat_type.fndds_75202021`) — contains FNDDS survey/preparation qualifier
- Asparagus, fresh, cooked, no added fat (`global.asparagus_fresh_cooked_no_added_fat.fndds_75202011`) — contains FNDDS survey/preparation qualifier

Representative **questionable** examples:
- Abalone (`global.abalone.fndds_26301110`) — resembles a single food/preparation rather than a reusable dish
- Alfredo sauce (`global.alfredo_sauce.fndds_14650160`) — resembles a single food/preparation rather than a reusable dish
- Arepa Dominicana (`global.arepa_dominicana.fndds_52220110`) — resembles a single food/preparation rather than a reusable dish
- Armadillo (`global.armadillo.fndds_23340100`) — resembles a single food/preparation rather than a reusable dish
- Artichoke dip (`global.artichoke_dip.fndds_14620110`) — resembles a single food/preparation rather than a reusable dish

## Ingredient-alias gap analysis

Coverage assumes current multilingual ingredient aliases plus hypothetical aliases for the N most frequent IngredientIDs. Occurrence coverage counts recipe-ingredient rows; full-recipe coverage requires every IngredientID in the recipe to be covered.

| Hypothetical top-N alias expansion | Covered IngredientIDs | Ingredient occurrences covered | Trusted recipes fully covered |
|---:|---:|---:|---:|
| 0 | 4 | 0.07% | 0.00% (0) |
| 50 | 54 | 55.16% | 5.26% (147) |
| 100 | 104 | 68.55% | 18.79% (525) |
| 250 | 254 | 83.32% | 46.24% (1,292) |
| 500 | 503 | 92.22% | 72.98% (2,039) |

### Top 100 ingredients by recipe frequency

| Rank | IngredientID | Name | Recipe occurrences | Existing aliases | Multilingual languages |
|---:|---|---|---:|---:|---:|
| 1 | `salt_table.usda_sr_02047` | Salt, table | 1813 | 0 | 0 |
| 2 | `vegetable_oil_nfs.usda_fndds_82101000` | Vegetable oil, NFS | 796 | 0 | 0 |
| 3 | `beverages_water_tap_drinking.usda_sr_14411` | Beverages, water, tap, drinking | 358 | 0 | 0 |
| 4 | `egg_whole_raw_fresh.usda_sr_01123` | Egg, whole, raw, fresh | 303 | 0 | 0 |
| 5 | `sugars_granulated.usda_sr_19335` | Sugars, granulated | 240 | 0 | 0 |
| 6 | `oil_or_table_fat_nfs.usda_fndds_81200100` | Oil or table fat, NFS | 216 | 0 | 0 |
| 7 | `wheat_flour_white_all_purpose_enriched_bleached.usda_sr_20081` | Wheat flour, white, all-purpose, enriched, bleached | 195 | 0 | 0 |
| 8 | `onions_raw.usda_sr_11282` | Onions, raw | 193 | 0 | 0 |
| 9 | `milk_nfs.usda_fndds_11100000` | Milk, NFS | 179 | 0 | 0 |
| 10 | `cheese_as_ingredient_in_sandwiches.usda_fndds_99991400` | Cheese as ingredient in sandwiches | 149 | 0 | 0 |
| 11 | `rice_white_long_grain_regular_enriched_cooked.usda_sr_20045` | Rice, white, long-grain, regular, enriched, cooked | 145 | 0 | 0 |
| 12 | `garlic_raw.usda_sr_11215` | Garlic, raw | 132 | 0 | 0 |
| 13 | `bread_white_commercially_prepared_includes_soft_bread_cr.usda_sr_18069` | Bread, white, commercially prepared (includes soft bread crumbs) | 126 | 0 | 0 |
| 14 | `chicken_ns_as_to_part_rotisserie_skin_not_eaten.usda_fndds_24102070` | Chicken, NS as to part, rotisserie, skin not eaten | 122 | 0 | 0 |
| 15 | `onions_cooked_boiled_drained_without_salt.usda_sr_11283` | Onions, cooked, boiled, drained, without salt | 110 | 0 | 0 |
| 16 | `beverages_water_tap_municipal.usda_sr_14429` | Beverages, water, tap, municipal | 109 | 0 | 0 |
| 17 | `celery_raw.usda_sr_11143` | Celery, raw | 106 | 0 | 0 |
| 18 | `tomato_products_canned_sauce.usda_sr_11549` | Tomato products, canned, sauce | 97 | 0 | 0 |
| 19 | `pasta_cooked_enriched_without_added_salt.usda_sr_20121` | Pasta, cooked, enriched, without added salt | 96 | 0 | 0 |
| 20 | `butter_salted.usda_sr_01001` | Butter, salted | 91 | 0 | 0 |
| 21 | `breading_or_batter_as_ingredient_in_food.usda_fndds_99995000` | Breading or batter as ingredient in food | 90 | 0 | 0 |
| 22 | `corn_sweet_yellow_frozen_kernels_cut_off_cob_boiled_drai.usda_sr_11179` | Corn, sweet, yellow, frozen, kernels cut off cob, boiled, drained, without salt | 81 | 0 | 0 |
| 23 | `cheese_cheddar_includes_foods_for_usda_s_food_distributi.usda_sr_01009` | Cheese, cheddar (Includes foods for USDA's Food Distribution Program) | 75 | 0 | 0 |
| 24 | `beef_round_top_round_steak_separable_lean_and_fat_trimme.usda_sr_13893` | Beef, round, top round steak, separable lean and fat, trimmed to 1/8" fat, all grades, cooked, broiled | 74 | 0 | 0 |
| 25 | `soy_sauce_made_from_soy_and_wheat_shoyu.usda_sr_16123` | Soy sauce made from soy and wheat (shoyu) | 73 | 0 | 0 |
| 26 | `broccoli_frozen_chopped_cooked_boiled_drained_without_sa.usda_sr_11093` | Broccoli, frozen, chopped, cooked, boiled, drained, without salt | 72 | 0 | 0 |
| 27 | `olive_oil` | Olive oil | 72 | 0 | 0 |
| 28 | `table_fat_nfs.usda_fndds_81100000` | Table fat, NFS | 70 | 0 | 0 |
| 29 | `onions_spring_or_scallions_includes_tops_and_bulb_raw.usda_sr_11291` | Onions, spring or scallions (includes tops and bulb), raw | 68 | 0 | 0 |
| 30 | `potatoes_boiled_cooked_without_skin_flesh_without_salt.usda_sr_11367` | Potatoes, boiled, cooked without skin, flesh, without salt | 68 | 0 | 0 |
| 31 | `carrots_frozen_cooked_boiled_drained_without_salt.usda_sr_11131` | Carrots, frozen, cooked, boiled, drained, without salt | 67 | 0 | 0 |
| 32 | `rolls_hamburger_or_hotdog_plain.usda_sr_18350` | Rolls, hamburger or hotdog, plain | 66 | 0 | 0 |
| 33 | `cheese_and_queso_as_ingredient.usda_fndds_99991410` | Cheese and Queso as ingredient | 65 | 0 | 0 |
| 34 | `gravy_chicken_canned_or_bottled_ready_to_serve.usda_sr_06119` | Gravy, chicken, canned or bottled, ready-to-serve | 65 | 0 | 0 |
| 35 | `noodles_egg_enriched_cooked.usda_sr_20110` | Noodles, egg, enriched, cooked | 65 | 0 | 0 |
| 36 | `tomatoes_red_ripe_raw_year_round_average.usda_sr_11529` | Tomatoes, red, ripe, raw, year round average | 65 | 0 | 0 |
| 37 | `onions_cooked_as_ingredient.usda_fndds_99997510` | Onions, cooked, as ingredient | 64 | 0 | 0 |
| 38 | `beans_snap_green_frozen_cooked_boiled_drained_without_sa.usda_sr_11061` | Beans, snap, green, frozen, cooked, boiled, drained without salt | 63 | 0 | 0 |
| 39 | `tortillas_ready_to_bake_or_fry_flour_refrigerated.usda_sr_18364` | Tortillas, ready-to-bake or -fry, flour, refrigerated | 61 | 0 | 0 |
| 40 | `cheese_parmesan_grated.usda_sr_01032` | Cheese, parmesan, grated | 60 | 0 | 0 |
| 41 | `spices_pepper_black.usda_sr_02030` | Spices, pepper, black | 59 | 0 | 0 |
| 42 | `wheat_bread_as_ingredient_in_sandwiches.usda_fndds_99995130` | Wheat bread as ingredient in sandwiches | 56 | 0 | 0 |
| 43 | `ginger_root_raw.usda_sr_11216` | Ginger root, raw | 55 | 0 | 0 |
| 44 | `peppers_sweet_green_cooked_boiled_drained_without_salt.usda_sr_11334` | Peppers, sweet, green, cooked, boiled, drained, without salt | 54 | 0 | 0 |
| 45 | `salad_dressing_mayonnaise_regular.usda_sr_04025` | Salad dressing, mayonnaise, regular | 54 | 0 | 0 |
| 46 | `pasta_whole_wheat_cooked_includes_foods_for_usda_s_food.usda_sr_20125` | Pasta, whole-wheat, cooked (Includes foods for USDA's Food Distribution Program) | 53 | 0 | 0 |
| 47 | `breakfast_meat_as_ingredient_in_omelet.usda_fndds_99992230` | Breakfast meat as ingredient in omelet | 52 | 0 | 0 |
| 48 | `cheese_mozzarella_low_moisture_part_skim.usda_sr_01029` | Cheese, mozzarella, low moisture, part-skim | 51 | 0 | 0 |
| 49 | `potatoes_baked_flesh_without_salt.usda_sr_11363` | Potatoes, baked, flesh, without salt | 51 | 0 | 0 |
| 50 | `rice_brown_long_grain_cooked_includes_foods_for_usda_s_f.usda_sr_20037` | Rice, brown, long-grain, cooked (Includes foods for USDA's Food Distribution Program) | 51 | 0 | 0 |
| 51 | `beef_as_ingredient_in_recipes.usda_fndds_99992100` | Beef as ingredient in recipes | 50 | 0 | 0 |
| 52 | `pickle_relish_sweet.usda_sr_11945` | Pickle relish, sweet | 50 | 0 | 0 |
| 53 | `beef_ground_patties_frozen_cooked_broiled.usda_sr_13317` | Beef, ground, patties, frozen, cooked, broiled | 49 | 0 | 0 |
| 54 | `margarine_stick.usda_fndds_81102010` | Margarine, stick | 48 | 0 | 0 |
| 55 | `mirepoix_cooked_as_ingredient.usda_fndds_99997805` | Mirepoix, cooked, as ingredient | 48 | 0 | 0 |
| 56 | `egg_whole_cooked_hard_boiled.usda_sr_01129` | Egg, whole, cooked, hard-boiled | 47 | 0 | 0 |
| 57 | `bread_crumbs_dry_grated_plain.usda_sr_18079` | Bread, crumbs, dry, grated, plain | 46 | 0 | 0 |
| 58 | `broccoli_cooked_as_ingredient.usda_fndds_99997220` | Broccoli, cooked, as ingredient | 46 | 0 | 0 |
| 59 | `mushrooms_cooked_as_ingredient.usda_fndds_99997515` | Mushrooms, cooked, as ingredient | 45 | 0 | 0 |
| 60 | `peppers_sweet_green_raw.usda_sr_11333` | Peppers, sweet, green, raw | 45 | 0 | 0 |
| 61 | `pork_fresh_loin_whole_separable_lean_only_cooked_roasted.usda_sr_10027` | Pork, fresh, loin, whole, separable lean only, cooked, roasted | 45 | 0 | 0 |
| 62 | `carrots_cooked_boiled_drained_without_salt.usda_sr_11125` | Carrots, cooked, boiled, drained, without salt | 43 | 0 | 0 |
| 63 | `tomatoes_red_ripe_canned_packed_in_tomato_juice.usda_sr_11531` | Tomatoes, red, ripe, canned, packed in tomato juice | 43 | 0 | 0 |
| 64 | `pie_crust_standard_type_frozen_ready_to_bake_enriched_ba.usda_sr_18335` | Pie crust, standard-type, frozen, ready-to-bake, enriched, baked | 42 | 0 | 0 |
| 65 | `leavening_agents_baking_powder_double_acting_sodium_alum.usda_sr_18369` | Leavening agents, baking powder, double-acting, sodium aluminum sulfate | 41 | 0 | 0 |
| 66 | `soup_cream_of_mushroom_canned_condensed.usda_sr_06043` | Soup, cream of mushroom, canned, condensed | 41 | 0 | 0 |
| 67 | `chicken_as_ingredient_in_recipes.usda_fndds_99992405` | Chicken as ingredient in recipes | 40 | 0 | 0 |
| 68 | `potatoes_baked_flesh_and_skin_without_salt.usda_sr_11674` | Potatoes, baked, flesh and skin, without salt | 40 | 0 | 0 |
| 69 | `shortening_vegetable_household_composite.usda_sr_04615` | Shortening, vegetable, household, composite | 40 | 0 | 0 |
| 70 | `beef_ground.usda_fndds_21500100` | Beef, ground | 38 | 0 | 0 |
| 71 | `cheese_ricotta_whole_milk.usda_sr_01036` | Cheese, ricotta, whole milk | 37 | 0 | 0 |
| 72 | `carrots_raw.usda_sr_11124` | Carrots, raw | 35 | 0 | 0 |
| 73 | `cheese_sauce_prepared_from_recipe.usda_sr_01164` | Cheese sauce, prepared from recipe | 35 | 0 | 0 |
| 74 | `cornstarch.usda_sr_20027` | Cornstarch | 35 | 0 | 0 |
| 75 | `lemon_juice_raw.usda_sr_09152` | Lemon juice, raw | 35 | 0 | 0 |
| 76 | `refried_beans_canned_traditional_reduced_sodium.usda_sr_16403` | Refried beans, canned, traditional, reduced sodium | 35 | 0 | 0 |
| 77 | `tomatoes_as_ingredient_in_omelet.usda_fndds_99997802` | Tomatoes as ingredient in omelet | 34 | 0 | 0 |
| 78 | `vinegar_cider.usda_sr_02048` | Vinegar, cider | 34 | 0 | 0 |
| 79 | `dark_green_vegetables_as_ingredient_in_omelet.usda_fndds_99997800` | Dark green vegetables as ingredient in omelet | 32 | 0 | 0 |
| 80 | `ham_sliced_pre_packaged_deli_meat_96_fat_free_water_adde.usda_sr_07028` | Ham, sliced, pre-packaged, deli meat (96%fat free, water added) | 32 | 0 | 0 |
| 81 | `pork_sausage_link_patty_cooked_pan_fried.usda_sr_07064` | Pork sausage, link/patty, cooked, pan-fried | 32 | 0 | 0 |
| 82 | `wheat_bun_as_ingredient_in_sandwiches.usda_fndds_99995135` | Wheat bun as ingredient in sandwiches | 32 | 0 | 0 |
| 83 | `pork_cured_bacon_pre_sliced_cooked_pan_fried.usda_sr_10862` | Pork, cured, bacon, pre-sliced, cooked, pan-fried | 31 | 0 | 0 |
| 84 | `raisins_dark_seedless_includes_foods_for_usda_s_food_dis.usda_sr_09298` | Raisins, dark, seedless (Includes foods for USDA's Food Distribution Program) | 31 | 0 | 0 |
| 85 | `sauce_pasta_spaghetti_marinara_ready_to_serve.usda_sr_06931` | Sauce, pasta, spaghetti/marinara, ready-to-serve | 31 | 0 | 0 |
| 86 | `crustaceans_shrimp_mixed_species_cooked_moist_heat_may_c.usda_sr_15151` | Crustaceans, shrimp, mixed species, cooked, moist heat (may contain additives to retain moisture) | 30 | 0 | 0 |
| 87 | `cucumber_with_peel_raw.usda_sr_11205` | Cucumber, with peel, raw | 30 | 0 | 0 |
| 88 | `egg_yolk_raw_fresh.usda_sr_01125` | Egg, yolk, raw, fresh | 30 | 0 | 0 |
| 89 | `rice_white_long_grain_regular_raw_enriched.usda_sr_20044` | Rice, white, long-grain, regular, raw, enriched | 30 | 0 | 0 |
| 90 | `soup_beef_broth_or_bouillon_canned_ready_to_serve.usda_sr_06008` | Soup, beef broth or bouillon canned, ready-to-serve | 30 | 0 | 0 |
| 91 | `vinegar_distilled.usda_sr_02053` | Vinegar, distilled | 30 | 0 | 0 |
| 92 | `cream_fluid_heavy_whipping.usda_sr_01053` | Cream, fluid, heavy whipping | 29 | 0 | 0 |
| 93 | `green_pepper_cooked_as_ingredient.usda_fndds_99997520` | Green pepper, cooked, as ingredient | 29 | 0 | 0 |
| 94 | `sausage_italian_pork_mild_cooked_pan_fried.usda_sr_07089` | Sausage, Italian, pork, mild, cooked, pan-fried | 29 | 0 | 0 |
| 95 | `white_sauce_or_gravy.usda_fndds_13411000` | White sauce or gravy | 29 | 0 | 0 |
| 96 | `egg_whole_fried_ns_as_to_fat.usda_fndds_31105005` | Egg, whole, fried, NS as to fat | 28 | 0 | 0 |
| 97 | `olives_ripe_canned_small_extra_large.usda_sr_09193` | Olives, ripe, canned (small-extra large) | 28 | 0 | 0 |
| 98 | `tomato_products_canned_puree_without_salt_added.usda_sr_11547` | Tomato products, canned, puree, without salt added | 28 | 0 | 0 |
| 99 | `cream_sour_cultured.usda_sr_01056` | Cream, sour, cultured | 27 | 0 | 0 |
| 100 | `fish_tuna_light_canned_in_water_drained_solids_includes.usda_sr_15121` | Fish, tuna, light, canned in water, drained solids (Includes foods for USDA's Food Distribution Program) | 27 | 0 | 0 |

## Benchmark definition and ground truth

Exact base identity cases use the public explicit-weight path, which resolves trusted recipes before model creation. Modifier and intentional semantic-fallback cases use the public phrase path.

| ID | Input | Language | Cohort | Route | Expected RecipeID | Expected modifier |
|---|---|---|---|---|---|---|
| base-01 | 200 gram tavuklu pilav | tr | curated_seed | explicitWeight | `tr.tavuklu_pilav.default` | — |
| base-02 | 200 Gramm Spaghetti alla carbonara | de | curated_seed | explicitWeight | `it.spaghetti_carbonara.roman` | — |
| base-03 | 비빔밥 200그램 | ko | curated_seed | explicitWeight | `kr.bibimbap.default` | — |
| base-04 | 200 граммов борща | ru | curated_seed | explicitWeight | `ru.borscht.default` | — |
| base-05 | ラーメン200グラム | ja | curated_seed | explicitWeight | `jp.ramen.shoyu` | — |
| base-06 | 200 gramos de paella de marisco | es | curated_seed | explicitWeight | `es.paella.seafood` | — |
| base-07 | 200 ग्राम चिकन बिरयानी | hi | curated_seed | explicitWeight | `in.chicken_biryani.default` | — |
| base-08 | 200g beef pho | en | curated_seed | explicitWeight | `vn.pho.beef` | — |
| base-09 | 200g shrimp pad thai | en | curated_seed | explicitWeight | `th.pad_thai.shrimp` | — |
| base-10 | 200 grammes de ratatouille | fr | curated_seed | explicitWeight | `fr.ratatouille.default` | — |
| base-11 | 200g pork schnitzel | en | curated_seed | explicitWeight | `de.schnitzel.pork` | — |
| base-12 | 200 غرام حمص | ar | curated_seed | explicitWeight | `me.hummus.default` | — |
| base-13 | 200g beef taco | en | curated_seed | explicitWeight | `mx.beef_taco.default` | — |
| base-14 | 200克蛋炒饭 | zh | curated_seed | explicitWeight | `cn.fried_rice.egg` | — |
| base-15 | 200 grammi di carbonara | it | curated_seed | explicitWeight | `it.spaghetti_carbonara.roman` | — |
| base-16 | 200g falafel | en | imported_usda | explicitWeight | `global.falafel.fndds_41209000` | — |
| base-17 | 200g sushi | en | imported_usda | explicitWeight | `global.sushi_nfs.fndds_58151100` | — |
| base-18 | 200g beef curry | en | imported_usda | explicitWeight | `global.beef_curry.fndds_27116100` | — |
| base-19 | 200g chicken curry | en | imported_usda | explicitWeight | `global.chicken_curry.fndds_27146150` | — |
| base-20 | 200g fish curry | en | imported_usda | explicitWeight | `global.fish_curry.fndds_27150320` | — |
| base-21 | 200g lentil curry | en | imported_usda | explicitWeight | `global.lentil_curry.fndds_41311030` | — |
| base-22 | 200g vegetable curry | en | imported_usda | explicitWeight | `global.vegetable_curry.fndds_75440600` | — |
| base-23 | 200g beef enchilada | en | imported_usda | explicitWeight | `global.enchilada_beef.fndds_58102810` | — |
| base-24 | 200g chicken enchilada | en | imported_usda | explicitWeight | `global.enchilada_chicken.fndds_58102830` | — |
| base-25 | 200g meatless enchilada | en | imported_usda | explicitWeight | `global.enchilada_no_meat.fndds_58102840` | — |
| base-26 | 200g homemade meat lasagna | en | imported_usda | explicitWeight | `global.lasagna_with_meat_home_recipe.fndds_58130015` | — |
| base-27 | 200g vegetable lasagna | en | imported_usda | explicitWeight | `global.lasagna_meatless_with_vegetables.fndds_58130320` | — |
| base-28 | 200g New England clam chowder | en | imported_usda | explicitWeight | `global.soup_new_england_clam_chowder.fndds_28355110` | — |
| base-29 | 200g gumbo with rice | en | imported_usda | explicitWeight | `global.gumbo_with_rice.fndds_27363000` | — |
| base-30 | 200g jambalaya with meat and rice | en | imported_usda | explicitWeight | `global.jambalaya_with_meat_and_rice.fndds_27363100` | — |
| base-31 | 200g chicken and dumplings | en | imported_usda | explicitWeight | `global.chicken_or_turkey_with_dumplings.fndds_27246100` | — |
| base-32 | 200g plain French toast | en | imported_usda | explicitWeight | `global.french_toast_plain.fndds_55301000` | — |
| base-33 | 200g plain pancakes | en | imported_usda | explicitWeight | `global.pancakes_plain.fndds_55101000` | — |
| base-34 | 200g club sandwich on wheat | en | imported_usda | explicitWeight | `global.club_sandwich_on_wheat.fndds_27540125` | — |
| base-35 | 200g tiramisu | en | imported_usda | explicitWeight | `global.tiramisu.fndds_13252600` | — |
| base-36 | 200g black bean salad | en | imported_usda | explicitWeight | `global.black_bean_salad.fndds_41203030` | — |
| base-37 | 200g falafel sandwich | en | imported_usda | explicitWeight | `global.falafel_sandwich.fndds_41901030` | — |
| base-38 | 200g chicken pad thai | en | imported_usda | explicitWeight | `global.pad_thai_with_chicken.fndds_58137230` | — |
| base-39 | 200g California sushi roll | en | imported_usda | explicitWeight | `global.sushi_roll_california.fndds_58151180` | — |
| base-40 | 200g beignet | en | imported_usda | explicitWeight | `global.beignet.fndds_53520510` | — |
| base-41 | 200g banana | en | intentional_fallback | explicitWeight | `none` | — |
| base-42 | 200g grilled chicken breast | en | intentional_fallback | explicitWeight | `none` | — |
| base-43 | 200g tofu scramble | en | intentional_fallback | phrase | `none` | — |
| base-44 | 200g chicken shawarma plate | en | intentional_fallback | phrase | `none` | — |
| base-45 | 200g quinoa avocado bowl | en | intentional_fallback | phrase | `none` | — |
| mod-01 | 200 gram tavuklu pilav, tavuksuz | tr | curated_seed | phrase | `tr.tavuklu_pilav.default` | remove chicken |
| mod-02 | 200g spaghetti carbonara without bacon | en | curated_seed | phrase | `it.spaghetti_carbonara.roman` | remove bacon |
| mod-03 | 200 Gramm Bibimbap ohne Ei | de | curated_seed | phrase | `kr.bibimbap.default` | remove egg |
| mod-04 | 200 gramos de paella con 30 gramos extra de camarones | es | curated_seed | phrase | `es.paella.seafood` | increase shrimp 30g |
| mod-05 | 200 grammes de ratatouille sans aubergine | fr | curated_seed | phrase | `fr.ratatouille.default` | remove eggplant |
| mod-06 | 200 grammi di carbonara con 20 grammi di parmigiano in più | it | curated_seed | phrase | `it.spaghetti_carbonara.roman` | increase parmesan 20g |
| mod-07 | 200 граммов борща без сметаны | ru | curated_seed | phrase | `ru.borscht.default` | remove sour_cream |
| mod-08 | 卵なしのラーメン200グラム | ja | curated_seed | phrase | `jp.ramen.shoyu` | remove egg |
| mod-09 | 계란 없이 비빔밥 200그램 | ko | curated_seed | phrase | `kr.bibimbap.default` | remove egg |
| mod-10 | 不要鸡蛋的200克蛋炒饭 | zh | curated_seed | phrase | `cn.fried_rice.egg` | remove egg |
| mod-11 | 200 غرام حمص بدون زيت زيتون | ar | curated_seed | phrase | `me.hummus.default` | remove olive_oil |
| mod-12 | 200 ग्राम चिकन बिरयानी बिना दही | hi | curated_seed | phrase | `in.chicken_biryani.default` | remove yogurt |
| mod-13 | 200g cheeseburger with 25g extra cheese | en | curated_seed | phrase | `us.cheeseburger.default` | increase cheddar 25g |
| mod-14 | 200g beef taco with less beef | en | curated_seed | phrase | `mx.beef_taco.default` | decrease beef |

## Live public-API results

Executed 45 of 59 cases; 40 completed successfully. The remaining cases are retained as failures, timeouts, safety refusals, or not-executed outcomes after an earlier case terminated their predefined batch.

| Metric | Result |
|---|---:|
| Trusted RecipeID hit rate | 70.37% |
| localRecipe rate | 64.41% |
| localNutrition rate | 3.39% |
| modelAssistedRecipe rate | 0.00% |
| modelNutrition rate | 0.00% |
| Failure/timeout/safety-refusal rate | 8.47% (5/59) |
| Not executed after batch termination | 23.73% (14/59) |
| Overall non-success rate | 32.20% (19/59) |
| Mass-conservation pass rate | 100.00% |
| Raw modifier accuracy among successful modifier parses | 66.67% (2/3) |
| Product-semantic modifier accuracy (excluding mod-13 spec issue) | 100.00% |
| Average / median / p95 case latency | 7487.24 / 1.00 / 63586.80 ms |
| FoundationModels requests | 17 |
| External watchdog terminations | 0 |
| Batch hard-timeout terminations | 0 |
| Internal model-timeout batch stops | 4 |

### Results by language

| Language | Cases | Successful | Recipe hits | Failure/timeout/refusal | Not executed | Modifier correct |
|---|---:|---:|---:|---:|---:|---:|
| ar | 2 | 1 | 1 | 0 | 1 | 0 |
| de | 2 | 1 | 1 | 0 | 1 | 0 |
| en | 37 | 30 | 28 | 2 | 5 | 1 |
| es | 2 | 1 | 1 | 0 | 1 | 0 |
| fr | 2 | 1 | 1 | 0 | 1 | 1 |
| hi | 2 | 0 | 0 | 1 | 1 | 0 |
| it | 2 | 1 | 1 | 1 | 0 | 0 |
| ja | 2 | 1 | 1 | 0 | 1 | 0 |
| ko | 2 | 1 | 1 | 0 | 1 | 0 |
| ru | 2 | 1 | 1 | 0 | 1 | 0 |
| tr | 2 | 1 | 1 | 0 | 1 | 0 |
| zh | 2 | 1 | 1 | 1 | 0 | 0 |

### Results by cohort

| Cohort | Cases | Successful | Recipe hits | Failure/timeout/refusal | Not executed |
|---|---:|---:|---:|---:|---:|
| curated_seed | 29 | 13 | 13 | 3 | 13 |
| imported_usda | 25 | 25 | 25 | 0 | 0 |
| intentional_fallback | 5 | 2 | 0 | 2 | 1 |

### Results by input script

| Script | Cases | Successful | Recipe hits | Failure/timeout/refusal | Not executed |
|---|---:|---:|---:|---:|---:|
| Latin | 47 | 35 | 33 | 3 | 9 |
| non-Latin | 12 | 5 | 5 | 2 | 5 |

### Provenance breakdown

| Provenance | Count |
|---|---:|
| localRecipe | 38 |
| localNutrition | 2 |

### Most common fallback/failure reasons
- not executed after an earlier case terminated its batch: 14
- FoundationModels parse timed out: 4
- recipe miss resolved by local nutrition: 2
- Response may contain sensitive or unsafe content: 1

### Ten best-performing imported recipes
- 200g falafel → `global.falafel.fndds_41209000`; 1031 kcal for 200g
- 200g sushi → `global.sushi_nfs.fndds_58151100`; 189 kcal for 200g
- 200g beef curry → `global.beef_curry.fndds_27116100`; 225 kcal for 200g
- 200g chicken curry → `global.chicken_curry.fndds_27146150`; 215 kcal for 200g
- 200g fish curry → `global.fish_curry.fndds_27150320`; 186 kcal for 200g
- 200g lentil curry → `global.lentil_curry.fndds_41311030`; 223 kcal for 200g
- 200g vegetable curry → `global.vegetable_curry.fndds_75440600`; 172 kcal for 200g
- 200g beef enchilada → `global.enchilada_beef.fndds_58102810`; 378 kcal for 200g
- 200g chicken enchilada → `global.enchilada_chicken.fndds_58102830`; 352 kcal for 200g
- 200g meatless enchilada → `global.enchilada_no_meat.fndds_58102840`; 327 kcal for 200g

### Special-case analysis

- `mod-13` is an **evaluation-spec issue**, not a product failure. Existing semantics say: The stated meal mass is final unless the user clearly says the modifier is additional outside the base quantity. The existing finalMeal path reserves explicit ingredient grams inside the final mass. Therefore the consistent final mass is **200g**, not the benchmark's 225g. The result contains 46g cheese: approximately 21g base cheese from the remaining 175g plus the explicit 25g increase, while total mass remains 200g.
- `base-43` is recorded exactly as a **fallback/model-availability failure**: `Response may contain sensitive or unsafe content`. No workaround or prompt change was attempted.

## Strengths

- The database is internally relational: trusted recipes reference existing IngredientIDs and nutrition rows, with normalized ratios and explicit provenance.
- The expansion adds broad prepared-food coverage across multiple dish categories, with deterministic energy calculation.
- Recipe aliases cover 34 languages and several major non-Latin scripts for a small set of prominent dishes.
- Stable RecipeID and IngredientID boundaries make invariant checking and regression benchmarking practical.

## Weaknesses

- FNDDS dominates the recipe population; many identities encode survey/preparation qualifiers rather than reusable canonical dishes.
- Cuisine and region metadata are unspecified for most records.
- Only 11 ingredient-alias rows exist, so multilingual ingredient-level modifier resolution is far behind recipe-level aliasing.
- Many closely related survey variants create identity ambiguity and inflate apparent dish coverage.
- Serving sizes inherited from FNDDS often describe a reference amount, not a natural meal serving.

## Highest-value next actions

1. Add a non-destructive canonicality/reusability gate plus family grouping for near-duplicate FNDDS variants, keeping survey records available without treating all of them as canonical dishes.
2. Add reviewed multilingual aliases for the top 100–250 IngredientIDs; top-250 coverage reaches 83.32% of ingredient occurrences and 46.24% of complete trusted recipes.
3. Audit Unicode normalization and exact alias resolution across major non-Latin scripts; the Hindi biryani alias missed deterministic resolution and fell into a model timeout.
4. Make FoundationModels cancellation hard-bounded at a process boundary and reduce the four sequential requests used for known-recipe modifiers; four cases stopped at the internal timeout and p95 latency was about 63.6 seconds.
5. Formalize quantity-scope wording in benchmark specifications and regression fixtures so final-meal versus base-plus-addition expectations cannot be ambiguous, as demonstrated by mod-13.

## Artifacts

- `Data/Reports/database_evaluation.json` — full statistics, raw benchmark ground truth/results, samples, and record-level flags.
- `Data/Reports/database_evaluation.md` — human-readable evaluation report.

No production data or behavior was modified, and no commit was created.
