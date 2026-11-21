# 学院人物：耳廓与全身解剖结构

输入是上一轮已审计的七位独立角色：侦探、卢西安、沃德、沈鼎、霍铎、阮清月、代管者。雀儿不在这一批下载网格里。只编辑审阅底模，保留原游戏资源和侦探 177 cm、6.5 头身的比例设定。

## 参考资料怎么用到模型上

| 参考 | 本轮落实 |
| --- | --- |
| Anatomy.app：[Auricle](https://anatomy.app/encyclopedia/auricle) | 耳轮是外缘隆起，对耳轮与外缘之间有耳舟，耳屏在耳甲腔前，耳垂在下。以头侧原边界拼接定向闭壳，低模 3 圈、高分辨率模 4 圈，另建凹腔底。分左右检查局部自交；保留各人的耳位、耳宽和耳长。 |
| Blender Studio：[Planar Torso](https://studio.blender.org/training/stylized-character-workflow/5d7f7dcd9889b3993224bea2/)、[Planar Arms & Legs](https://studio.blender.org/training/stylized-character-workflow/5d7f7e61db37a94301d88fef/) | 用大面定胸廓、骨盆和四肢截面，再加入肌腹及骨点，靠纯色斜光验收实际转折。 |
| OpenStax：[肩带与上肢肌](https://openstax.org/books/anatomy-and-physiology-2e/pages/11-5-muscles-of-the-pectoral-girdle-and-upper-limbs) | 胸肌由胸骨、锁骨一侧向上臂汇拢，形成腋前襞；三角肌盖住肩头，在上臂上段收尖。二头在前、三头在后；肱桡肌沿肘外侧过渡到前臂，厚度向腕部收束。按左右手臂的实际截面雕塑。 |
| OpenStax：[腹壁与胸廓](https://openstax.org/books/anatomy-and-physiology-2e/pages/11-4-axial-muscles-of-the-abdominal-wall-and-thorax) | 肋弓以下保留腹外斜肌走向，髂嵴形成腰外侧的转折；背阔肌和腰背肌保持宽窄区别。阮清月保留柔和的胸廓、腰侧及大腿过渡。 |
| OpenStax：[骨盆与下肢](https://openstax.org/books/anatomy-and-physiology-2e/pages/11-6-appendicular-muscles-of-the-pelvic-girdle-and-lower-limbs) | 膝内上方的股内侧肌比外侧肌更低，髌骨单独建立骨点。小腿前侧用胫骨面，后侧用不齐平的腓肠肌两头，沿跟腱收向踝部。保留裆部两腿汇合处原有网格。 |

所有体块都体现在顶点位置中。眼睑和唇缘的原有编号保留，双眼、眉片与内衣是分件。体型强度按角色设定：侦探精瘦、诗人窄身、沃德倒三角、沈鼎厚腹、霍铎厚肩臂、阮清月柔和、代管者修长。

## 审阅与复现

- `cast-auricle.jpg`：上版侧面、本轮侧面、本轮低模线框。个人审阅图提供前、侧、后视及耳廓高低模对照。
- `cast-front-projection.jpg`：参考裁切、贴到实际网格的投影、纯色几何，使用同一正交坐标。`cast-solid-before-after.jpg`：实际形体前后对照。
- 本轮身体低模加双眼与眉片为 **4,970–4,996** 三角面，独立衣件和胡须另计。侦探、沃德、沈鼎的身体低模全四边面，其余各有两个三角面。七个高低模的身体网格均通过闭壳、非流形边及非邻接三角静态自交检查。`blender-audit.json` 记录实测值。`.blend` 有左右耳廓顶点组，GLB 只有纯色材质。
- `final-measurements.json` 基于 Blender 审计后的实际网格。以高度为单位，封闭体等密度重心相对前版偏差 **0.32%–0.79%**。正面轮廓 IoU **92.7%–94.5%**，比前版下降约 **1.6–2.3 个百分点**。耳部外沿及肌肉新轮廓在正投影中确有变化。IoU 用于量化正面轮廓；纯色视图仍能看出脸部侧面、膝足和参考图的差别，绑骨动作未验收。

### 脸部待重布线

`cast-nose-diagnostic.jpg` 用纯色侧面和斜侧放大展示鼻区。侦探、沃德和阮清月的鼻梁、尖和翼仍挤在同一片面上；霍铎、代管者有凸出的轮廓点，鼻翼和鼻底缺乏分界。鼻区下轮需要替换连接眼间、内眼角与上唇之间的面片，建立鼻根、鼻尖、双侧鼻翼和鼻底的独立体积，然后检查眼窝与口缝。当前交付是耳廓与身体修订的审阅版，脸模须重审。

```powershell
$d='.runtime/academy-body-pilot'
$ref="$d/anatomy-geometry-v7/reference-lineup.jpg"
$base="$d/anatomy-photo-relief-final"
$out="$d/anatomy-structure-v3"
$blender='C:\Program Files\Blender Foundation\Blender 4.2\blender.exe'
python tools/academy_cast/anatomy_construct.py $base $ref $out
& $blender -b --factory-startup --threads 2 --python-exit-code 1 --python tools/academy_cast/anatomy_geometry_blender.py -- $out "$d/source-local-delivery"
python tools/academy_cast/anatomy_structural_review.py $ref "$base/fitted" "$out/fitted" "$out/lookdev"
python -m unittest discover -s tools/academy_cast -p 'test_anatomy*.py'
python -m unittest discover -s tools/academy_cast -p 'test_tripo_surface.py'
```
