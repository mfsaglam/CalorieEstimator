PRAGMA foreign_keys = ON;
BEGIN;

CREATE TABLE recipes (
    id TEXT PRIMARY KEY,
    canonical_name TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    cuisine TEXT,
    region TEXT,
    variant TEXT,
    default_serving_grams INTEGER CHECK (default_serving_grams > 0)
);
CREATE TABLE recipe_aliases (
    recipe_id TEXT NOT NULL REFERENCES recipes(id),
    alias TEXT NOT NULL,
    normalized_alias TEXT NOT NULL,
    language_code TEXT,
    locale_identifier TEXT
);
CREATE INDEX recipe_alias_lookup ON recipe_aliases(normalized_alias);
CREATE TABLE ingredients (
    id TEXT PRIMARY KEY,
    canonical_name TEXT NOT NULL,
    nutrition_lookup_name TEXT NOT NULL
);
CREATE TABLE recipe_ingredients (
    recipe_id TEXT NOT NULL REFERENCES recipes(id),
    ingredient_id TEXT NOT NULL REFERENCES ingredients(id),
    position INTEGER NOT NULL,
    ratio REAL NOT NULL CHECK (ratio > 0 AND ratio <= 1),
    PRIMARY KEY (recipe_id, ingredient_id)
);

INSERT INTO ingredients VALUES
('rice','Rice','rice'),('chicken','Chicken','chicken'),('butter','Butter','butter'),('olive_oil','Olive oil','olive oil'),
('pasta','Pasta','pasta'),('egg','Egg','egg'),('bacon','Pancetta or bacon','bacon'),('parmesan','Parmesan','parmesan'),('black_pepper','Black pepper','black pepper'),
('noodle','Noodles','noodle'),('broth','Broth','broth'),('pork','Pork','pork'),('green_onion','Green onion','green onion'),
('pea','Peas','pea'),('carrot','Carrot','carrot'),('soy_sauce','Soy sauce','soy sauce'),('yogurt','Yogurt','yogurt'),('onion','Onion','onion'),('spice','Spices','spice'),
('beef','Beef','beef'),('tortilla','Tortilla','tortilla'),('tomato','Tomato','tomato'),('lettuce','Lettuce','lettuce'),('cheddar','Cheese','cheddar'),
('chickpea','Chickpeas','chickpea'),('tahini','Tahini','tahini'),('lemon','Lemon','lemon'),('garlic','Garlic','garlic'),
('bread','Bread or bun','bread'),('ketchup','Ketchup','ketchup'),('spinach','Spinach','spinach'),('mushroom','Mushroom','mushroom'),
('shrimp','Shrimp','shrimp'),('peanut','Peanuts','peanut'),('bean_sprout','Bean sprouts','bean sprout'),('sugar','Sugar','sugar'),('herbs','Fresh herbs','herbs'),
('fish','Fish','fish'),('eggplant','Eggplant','eggplant'),('zucchini','Zucchini','zucchini'),('bell_pepper','Bell pepper','bell pepper'),('flour','Flour','flour');

INSERT INTO recipes VALUES
('global.chicken_rice.default','Chicken Rice','chicken rice',NULL,NULL,'default',300),
('tr.tavuklu_pilav.default','Tavuklu Pilav','tavuklu pilav','Turkish','Turkey','default',300),
('it.spaghetti_carbonara.roman','Spaghetti Carbonara','spaghetti carbonara','Italian','Lazio','roman',300),
('jp.ramen.shoyu','Shoyu Ramen','shoyu ramen','Japanese','Japan','shoyu',550),
('cn.fried_rice.egg','Egg Fried Rice','egg fried rice','Chinese','China','egg',300),
('in.chicken_biryani.default','Chicken Biryani','chicken biryani','Indian','India','default',350),
('mx.beef_taco.default','Beef Taco','beef taco','Mexican','Mexico','default',120),
('me.hummus.default','Hummus','hummus','Middle Eastern',NULL,'default',150),
('us.cheeseburger.default','Cheeseburger','cheeseburger','American','United States','default',250),
('kr.bibimbap.default','Bibimbap','bibimbap','Korean','Korea','default',450),
('th.pad_thai.shrimp','Shrimp Pad Thai','shrimp pad thai','Thai','Thailand','shrimp',350),
('vn.pho.beef','Beef Pho','beef pho','Vietnamese','Vietnam','beef',600),
('es.paella.seafood','Seafood Paella','seafood paella','Spanish','Valencia','seafood',400),
('fr.ratatouille.default','Ratatouille','ratatouille','French','Provence','default',300),
('de.schnitzel.pork','Pork Schnitzel','pork schnitzel','German','Germany','pork',220);

INSERT INTO recipe_aliases VALUES
('global.chicken_rice.default','chicken rice','chicken rice','en',NULL),
('global.chicken_rice.default','Hähnchen mit Reis','hähnchen mit reis','de','de-DE'),
('global.chicken_rice.default','arroz con pollo','arroz con pollo','es',NULL),
('global.chicken_rice.default','チキンライス','チキンライス','ja','ja-JP'),
('global.chicken_rice.default','鸡肉饭','鸡肉饭','zh',NULL),
('tr.tavuklu_pilav.default','tavuklu pilav','tavuklu pilav','tr','tr-TR'),
('tr.tavuklu_pilav.default','Turkish chicken rice','turkish chicken rice','en',NULL),
('it.spaghetti_carbonara.roman','spaghetti carbonara','spaghetti carbonara','en',NULL),
('it.spaghetti_carbonara.roman','carbonara','carbonara','it','it-IT'),
('it.spaghetti_carbonara.roman','carbonara','carbonara','en',NULL),
('jp.ramen.shoyu','shoyu ramen','shoyu ramen','en',NULL),
('jp.ramen.shoyu','醤油ラーメン','醤油ラーメン','ja','ja-JP'),
('cn.fried_rice.egg','egg fried rice','egg fried rice','en',NULL),
('cn.fried_rice.egg','蛋炒饭','蛋炒饭','zh','zh-CN'),
('in.chicken_biryani.default','chicken biryani','chicken biryani','en',NULL),
('in.chicken_biryani.default','चिकन बिरयानी','चिकन बिरयानी','hi','hi-IN'),
('mx.beef_taco.default','beef taco','beef taco','en',NULL),
('mx.beef_taco.default','taco de res','taco de res','es','es-MX'),
('me.hummus.default','hummus','hummus','en',NULL),
('me.hummus.default','حمص','حمص','ar',NULL),
('us.cheeseburger.default','cheeseburger','cheeseburger','en','en-US'),
('kr.bibimbap.default','bibimbap','bibimbap','en',NULL),
('kr.bibimbap.default','비빔밥','비빔밥','ko','ko-KR'),
('th.pad_thai.shrimp','shrimp pad thai','shrimp pad thai','en',NULL),
('th.pad_thai.shrimp','ผัดไทยกุ้ง','ผัดไทยกุ้ง','th','th-TH'),
('vn.pho.beef','beef pho','beef pho','en',NULL),
('vn.pho.beef','phở bò','phở bò','vi','vi-VN'),
('es.paella.seafood','seafood paella','seafood paella','en',NULL),
('es.paella.seafood','paella de marisco','paella de marisco','es','es-ES'),
('fr.ratatouille.default','ratatouille','ratatouille','fr','fr-FR'),
('de.schnitzel.pork','pork schnitzel','pork schnitzel','en',NULL),
('de.schnitzel.pork','Schweineschnitzel','schweineschnitzel','de','de-DE');

INSERT INTO recipe_ingredients VALUES
('global.chicken_rice.default','rice',1,.57),('global.chicken_rice.default','chicken',2,.37),('global.chicken_rice.default','butter',3,.04),('global.chicken_rice.default','olive_oil',4,.02),
('tr.tavuklu_pilav.default','rice',1,.57),('tr.tavuklu_pilav.default','chicken',2,.37),('tr.tavuklu_pilav.default','butter',3,.04),('tr.tavuklu_pilav.default','olive_oil',4,.02),
('it.spaghetti_carbonara.roman','pasta',1,.62),('it.spaghetti_carbonara.roman','egg',2,.16),('it.spaghetti_carbonara.roman','bacon',3,.12),('it.spaghetti_carbonara.roman','parmesan',4,.08),('it.spaghetti_carbonara.roman','black_pepper',5,.02),
('jp.ramen.shoyu','noodle',1,.50),('jp.ramen.shoyu','broth',2,.30),('jp.ramen.shoyu','pork',3,.10),('jp.ramen.shoyu','egg',4,.08),('jp.ramen.shoyu','green_onion',5,.02),
('cn.fried_rice.egg','rice',1,.65),('cn.fried_rice.egg','egg',2,.15),('cn.fried_rice.egg','pea',3,.08),('cn.fried_rice.egg','carrot',4,.05),('cn.fried_rice.egg','olive_oil',5,.04),('cn.fried_rice.egg','soy_sauce',6,.03),
('in.chicken_biryani.default','rice',1,.52),('in.chicken_biryani.default','chicken',2,.30),('in.chicken_biryani.default','yogurt',3,.08),('in.chicken_biryani.default','onion',4,.05),('in.chicken_biryani.default','olive_oil',5,.04),('in.chicken_biryani.default','spice',6,.01),
('mx.beef_taco.default','beef',1,.35),('mx.beef_taco.default','tortilla',2,.30),('mx.beef_taco.default','tomato',3,.10),('mx.beef_taco.default','lettuce',4,.10),('mx.beef_taco.default','cheddar',5,.10),('mx.beef_taco.default','onion',6,.05),
('me.hummus.default','chickpea',1,.60),('me.hummus.default','tahini',2,.20),('me.hummus.default','olive_oil',3,.10),('me.hummus.default','lemon',4,.07),('me.hummus.default','garlic',5,.03),
('us.cheeseburger.default','beef',1,.40),('us.cheeseburger.default','bread',2,.30),('us.cheeseburger.default','cheddar',3,.12),('us.cheeseburger.default','tomato',4,.06),('us.cheeseburger.default','lettuce',5,.06),('us.cheeseburger.default','onion',6,.04),('us.cheeseburger.default','ketchup',7,.02),
('kr.bibimbap.default','rice',1,.40),('kr.bibimbap.default','beef',2,.20),('kr.bibimbap.default','egg',3,.12),('kr.bibimbap.default','spinach',4,.08),('kr.bibimbap.default','carrot',5,.08),('kr.bibimbap.default','mushroom',6,.06),('kr.bibimbap.default','olive_oil',7,.03),('kr.bibimbap.default','soy_sauce',8,.03),
('th.pad_thai.shrimp','noodle',1,.45),('th.pad_thai.shrimp','shrimp',2,.18),('th.pad_thai.shrimp','egg',3,.12),('th.pad_thai.shrimp','peanut',4,.08),('th.pad_thai.shrimp','bean_sprout',5,.08),('th.pad_thai.shrimp','olive_oil',6,.05),('th.pad_thai.shrimp','sugar',7,.02),('th.pad_thai.shrimp','soy_sauce',8,.02),
('vn.pho.beef','broth',1,.45),('vn.pho.beef','noodle',2,.30),('vn.pho.beef','beef',3,.15),('vn.pho.beef','onion',4,.04),('vn.pho.beef','bean_sprout',5,.04),('vn.pho.beef','herbs',6,.02),
('es.paella.seafood','rice',1,.50),('es.paella.seafood','shrimp',2,.15),('es.paella.seafood','fish',3,.10),('es.paella.seafood','tomato',4,.08),('es.paella.seafood','pea',5,.06),('es.paella.seafood','olive_oil',6,.05),('es.paella.seafood','onion',7,.04),('es.paella.seafood','spice',8,.02),
('fr.ratatouille.default','eggplant',1,.25),('fr.ratatouille.default','zucchini',2,.20),('fr.ratatouille.default','tomato',3,.20),('fr.ratatouille.default','bell_pepper',4,.15),('fr.ratatouille.default','onion',5,.10),('fr.ratatouille.default','olive_oil',6,.08),('fr.ratatouille.default','garlic',7,.02),
('de.schnitzel.pork','pork',1,.58),('de.schnitzel.pork','bread',2,.15),('de.schnitzel.pork','egg',3,.08),('de.schnitzel.pork','flour',4,.08),('de.schnitzel.pork','olive_oil',5,.10),('de.schnitzel.pork','lemon',6,.01);

COMMIT;
