# 《同一夜》 · 第二轮三条主题旋律

这一轮重新写了三条女高旋律，分别让**合唱模仿、固定低音、重音交接**承担循环。三版同为 16 小节、4/4、♩=68、SATB＋钢琴＋大提琴＋钟。每首第一声都是女高独唱；同样用 MuseScore 自带 MS Basic / Choir Aahs 播放四条独立的人声轨，约 59 秒一首（含导出尾音）。上一轮 A–D 的文件保留，本轮未接入游戏。

| 版本 | 试听与谱 | 第一小节女高 | 对比听点 |
| --- | --- | --- | --- |
| **E · 回声室 / Echo Office** | [MP3](e-echo-office-ms-basic.mp3) · [PDF](e-echo-office.pdf) · [MuseScore](e-echo-office.mscz) · [MusicXML](e-echo-office.musicxml) | D5–G5–A♭5–G5 | **0:00–0:14。** 第 2、3、4 小节分别由女低、男高、男低接过首句，保持原节奏与音程，移到各自音区。大提琴到第 5 小节才进。 |
| **F · 夜班名册 / Night Ledger** | [MP3](f-night-ledger-ms-basic.mp3) · [PDF](f-night-ledger.pdf) · [MuseScore](f-night-ledger.mscz) · [MusicXML](f-night-ledger.musicxml) | E♭5–D5–E♭5–C5 | **0:04、0:21、0:39。** 大提琴在第 2、7、12 小节启动同一地线，上声的起句、换气和抬高音区各有自己的时点。 |
| **G · 破晓未至 / Broken Dawn** | [MP3](g-broken-dawn-ms-basic.mp3) · [PDF](g-broken-dawn.pdf) · [MuseScore](g-broken-dawn.mscz) · [MusicXML](g-broken-dawn.musicxml) · [开场谱图](g-score-preview.png) | A♭5–G5–E♭5–F5 | **0:28–0:40，0:55。** 钢琴的 3+3+2 重音交给大提琴；女高回到首句，钢琴留空。最后一声钟在第 16 小节第 3 拍，琴弓继续。 |

## 谱例与本轮的变化

- **Palestrina，《Sicut cervus》**：[所读 IMSLP 谱页（WIMA 版）](https://cdn.imslp.org/images/thumb/pdfs/56/e323fbd813299d2ade26cb84fa80aac39f0a8662.png)。第一行系统里，男高 m1 开唱；女低 m3、女高 m4 后半、男低 m6 后半各开始自己的「Sicut」。较早进入的声部已在继续唱下一部分。E 采用这种写法，把本曲的 D–G–A♭–G 动机先交给女高，再给女低 D–G–A♭–G、男高 G–C–D♭–C、男低 D–G–A♭–G；前三个回答都是原时值的移调，前一声部继续自己的句子。礼仪感由众声部掌握同一种唱法逐步产生。
- **Purcell，《狄多的哀歌》**：[所读 IMSLP 谱页（Les Éditions Outremontaises 版）](https://cdn.imslp.org/images/thumb/pdfs/d8/19a1ee786ed8bb497850980ad8a3be50c7b44c97.png)。m14–18 的 3/2 地线先以八度回到高 G，再经 F♯–F–E–E♭下到 D；m19 地线回到 G，上面的独唱还在唱长句。F 将这条**五小节模型**移到自己的 C 调域、改为 4/4，保留 C3–B2–B♭2–A2–A♭2–G2 半音下降，后半段改写为落向 E♭2、经 F2 回 G2。三轮大提琴地线逐音相同，女高在第三轮开头才重唱初始动机。
- **Mili《Between Two Worlds》暗界**：[交响改编谱](https://musescore.com/user/36430104/scores/10406389) m9 将连续运动从高处交给低声部。G 的钢琴在 m9 用八分音符，重音落在每小节第 **1、4、7** 个八分音符（即第 1 拍、第 2 拍后半、第 4 拍），m10 最后一组由大提琴接起。G 又把《用一生去梦》第二部分参考用的 G→A♭ 翻转为 **A♭→G**。返唱时低 G 已在运行，女高先以 A♭贴着它，再落 G；随后大提琴转向 C。前景的唱句呼吸，低处的重音不停。

## 测量与取舍

| 版 | 女高对下方声部：协和 / 四度 / 张力 | 返唱两小节：女高对最低音的张力 | 综合响度 | 真峰值 | LRA |
| --- | ---: | ---: | ---: | ---: | ---: |
| E | 87.2 / 6.7 / 6.1% | 6.7% | −20.00 LUFS | −3.70 dBTP | 10.8 LU |
| F | 74.5 / 6.6 / 18.9% | 25.0% | −20.00 LUFS | −4.46 dBTP | 10.0 LU |
| G | 89.0 / 7.2 / 3.8% | 20.0% | −20.00 LUFS | −4.31 dBTP | 10.5 LU |

- **F 做过一次从谱面出发的修订。** 初稿第三轮地线开始时，女高 D5 在 C2 上持续两拍，下一小节的末拍还有 A♭5/B♭2。定稿将前者减到一拍，A♭5 改为 G5，保留 m13 第 3 拍的 F5/B2 三全音，返唱的低音张力 **50% → 25%**。固定低音一个音没动，改变的是摩擦留多久、留在哪一拍。复算数据见 [score-metrics.json](score-metrics.json)。
- **G 是继续发展整首主题的首选。** E 的前四小节最适合拿来校准仪式性，F 最适合描写一整夜的耗损。G 用 m11 开头的持续一拍半的 A♭/G 冲突集中表达返唱压力；钟后仍保留低处运动。下一轮可先做一版仅把 E 的错位应答移到 G 的前段，其余织体保持 G，听神圣感能否加强而不冲淡脉搏。
- 音程算法沿用[上一轮说明](../README.md#第一轮测量--第二轮修改)：按谱面发声持续时间加权，四度单列，钟不参与统计；响度按最终 MP3 解码复测。三条音频用常量增益配平。三首都校验了女高独入、七条谱线的时值、SATB 音区次序、MuseScore 实际挂载的人声音源，并渲染检查全部六张谱页。建议听审时先固定音量，在表里的时点切换版本。

## 命令行复现

```powershell
python tools/music/theme_round_two.py
$dir = 'Music/theme-studies/round-two'
foreach ($stem in 'e-echo-office','f-night-ledger','g-broken-dawn') {
    python tools/music/render_musescore.py --profile 'MuseScore Basic' --score "$dir/$stem.musicxml" --out $dir
}
# PDF：MuseScore 转换模式 -o <PDF> <MusicXML>；开场谱图来自 PDF 第 1 页。
```
