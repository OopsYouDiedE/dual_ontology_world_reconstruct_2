# 《同一夜》 · 沉睡学院主旋律四版试奏

> [第二轮：三条新旋律的试听、总谱与测试](round-two/README.md) · 帕莱斯特里纳、珀塞尔与 Mili 的组合技法。

**本轮推荐继续写 D「没有明天」。** 四版每首 16 小节，4/4，♩=68，约 58 秒。前 3 拍只有女高；第 11–12 小节把第 1–2 小节女高声部原样唱回来。共享人声、室内混响和基本配器，便于把差异听成声部组织。当前为合成试奏，素材未接入游戏；旧稿保留。

| 版本 | MP3 | 总谱 | 可编辑 | 写作命题 |
| --- | --- | --- | --- | --- |
| A · Chapel（礼拜堂） | [试听](a-chapel.mp3) | [PDF](a-chapel.pdf) | [MusicXML](a-chapel.musicxml) | 女高先开口，之后女低、男高、男低依次搭成祈祷；重唱用随旋律换位的低音托住。 |
| B · Held Breath（屏息） | [试听](b-held-breath.mp3) | [PDF](b-held-breath.pdf) | [MusicXML](b-held-breath.musicxml) | 把低音 G 留在原地，测试女高经过 D♭、A♭ 时的摩擦，以及长时间停在同一低音的感受。 |
| C · Escapement（擒纵） | [试听](c-escapement.mp3) | [PDF](c-escapement.pdf) | [MusicXML](c-escapement.musicxml) | m9 钢琴每拍六音；m10 第 3 拍交给大提琴每拍两音。第二次起唱接在已经存在的拍子里；低音换到 C，给 A♭ 让位。 |
| D · No Tomorrow（没有明天） | [试听](d-no-tomorrow.mp3) | [PDF](d-no-tomorrow.pdf) | [MusicXML](d-no-tomorrow.musicxml) | 保留 C 的脉搏交接，收窄 B 的持续摩擦：把返唱的低音冲突集中在一拍，撤掉返唱第一小节钢琴，并把钟声提前到末小节开头。 |

另有 [D：钟后接回开头](d-next-turn.mp3)（约 14 秒）。全曲文件保留冷开场的女高独唱；这个摘录专门展示收尾的低脉搏如何经过接缝，走入下一轮。

## D · MuseScore 人声音色试听

- [开场四小节谱图](d-score-preview.png) · [三页总谱 PDF](d-no-tomorrow.pdf) · [MuseScore 原生工程](d-no-tomorrow.mscz) · [MusicXML](d-no-tomorrow.musicxml)。
- [MuseScore 内置 Choir Aahs 试听](d-no-tomorrow-ms-basic.mp3)（约 59 秒）。命令行生成；四条人声轨保留独立谱线、力度和原有入拍，使用 MuseScore 自带 MS Basic 的 Choir Aahs，原试听的自制合成声没有混入。这个内置版本四轨共用 Ah 音色，谱上的 Oo 留给支持该音色的播放库或演唱。成品为 **−20.01 LUFS / −5.23 dBTP / 10.7 LU LRA**，见 [测量记录](d-no-tomorrow-ms-basic.json)。
- 本机 MuseSampler 已加载，但 Muse Choir 资源有多个零字节文件；实际试导出时，四个人声轨都回退到 MS Basic。导出脚本默认验证四轨都确实使用 MuseSampler，失败时不会把回退文件交付为 Muse Choir。音色齐全后可在命令行重导同一份谱。

```powershell
python tools/music/render_musescore.py                            # 完整 Muse Choir；验证四轨音源
python tools/music/render_musescore.py --profile "MuseScore Basic"  # 此处交付的内置 Ah 试奏
```

## 来源与组合

- [《Une vie à rêver》官方录音](https://clairobscurexpedition33.bandcamp.com/track/une-vie-r-ver) 第二部分约 2:45 的起势，及 [A.E. 转写](https://musescore.com/user/36989239/scores/26303614) m67–68：取 **G→A♭** 这个具体的局部音高材料和「上声先起」的动作。这里让 G5、A♭5 各唱两拍，续成 G5–E♭5–D5 的回落；其后声线、四部组合和音色为本轮写作。试奏没有使用参考录音采样。
- Mili 的 [光界 SATB 改编](https://musescore.com/user/36430104/scores/10246609) 提供慢拍宗教咏唱的参照，[暗界总谱](https://musescore.com/user/36430104/scores/10406389) m5–6 展示了错开声部入口，m9 展示了把连续运动从钢琴快速细分交给低声部八分音符。本轮重新写了钢琴六连音的音列、低弦接续线及合唱内声。C/D 维持原速度，靠更换细分与音区改变时间感。
- [项目夜班流程](../../docs/design/night-watch.md)：钟声结算名册；一局之后仍可重新发册。开场咏唱是神圣秩序第一次显现，返唱让听者听见它已经在运行。结尾的 D5 对低 G 留着开放五度，钟带来仪式上的停顿，低弦仍继续走。

## D 的谱面听点

| 时点 | 小节和拍 | 听什么 |
| --- | --- | --- |
| 0:00–0:03 | m1 第 1–3 拍 | 只有女高。第 3 拍 G5 抬到 A♭5，半音发生时还没有和声规定它的方向；第 4 拍大提琴 A♭3 和女低 C4 才进来。 |
| 0:04–0:07 | m2 | 女高落回 G5，女低 E♭4 和大提琴 E♭3 先立住；男高第 1 拍后半入、男低第 3 拍入。几条线先后加入，逐步形成共同的祈祷。 |
| 0:28–0:35 | m9–m10 | 人声整段休止。钢琴上方的折返每拍六音（约 147 ms 一音），m10 后两拍钢琴停，大提琴用 G2 八分同音（约 441 ms 一音）接过计时。 |
| 0:35–0:40 | m11–m12 | 同一句从 G5 开始；底下已有 G2。女低 m11 第 2 拍入、男高在该拍后半入、男低第 3 拍后半才入，钢琴整小节留白。第 3 拍女高到 A♭5，低 G 继续半音对峙；第 4 拍低音换 C3，女高仍在原 A♭5，由复音程折八度的小二度松为小六度。声音没有靠抬响度来制造这一转变。 |
| 0:53 | m16 | 钟在第 1 拍打在 C，女高 D5 保持两拍即停；大提琴 G2 从头到尾有八个起音。钟可以结束这一局，末拍依然给下一遍开头留着时间。 |

## 第一轮测量 → 第二轮修改

分析量来自谱面和交付 MP3。详见 [metrics.json](metrics.json)。

| 版本 | 女高对下方各线：协和类 | 四度 | 张力类 | 返唱·女高对最低音：张力类 | 全曲响度 | 真峰值 | LRA |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A | 87.9% | 11.1% | 1.0% | 0.0% | −20.27 LUFS | −9.77 dBTP | 9.2 LU |
| B | 68.1% | 12.6% | 19.3% | 26.7% | −20.27 LUFS | −9.50 dBTP | 9.1 LU |
| C | 89.6% | 9.3% | 1.1% | 0.0% | −20.27 LUFS | −9.65 dBTP | 9.2 LU |
| D | 87.8% | 9.2% | 3.0% | 13.3% | −20.28 LUFS | −9.63 dBTP | 9.2 LU |

- **音程算法：**四拍各分成 12 格，统计女高发声时与每条正在发声的下方谱线的音程，按持续时值计权，复音程折回八度。协和类是同度/八度、大小三度、五度、大小六度；四度单列；二度、七度、三全音归入张力。排除钟的非谐共鸣，同时单独统计女高对最低音的关系。这个指标衡量配置和持续时间；音区、元音、演奏强度和和声上下文仍要在听审判断。逐声部检查了 SATB 音域次序，内声不交叉。
- **响度算法：**用 FFmpeg `loudnorm` 的输入计量读取成品 MP3 解码后的综合 LUFS、dBTP 和 LRA（[ITU-R BS.1770](https://www.itu.int/rec/R-REC-BS.1770/en)，[EBU Tech 3342](https://tech.ebu.ch/docs/tech/tech3342.pdf)）。统一按约 −20 LUFS 的试听目标做常量增益，没用压缩器或限制器；四版综合响度差 0.01 LU。真峰值表示可用裕量，LRA 适合用来对照本组段落起伏；两者都留到实机配合旁白与环境声时重定目标。
- **为什么保留 D：**B 的低 G 在返唱顶声的两个 A♭ 拍都不退，能显出压力，但全曲有接近五分之一的女高配对时值属于张力类。C 解决了「钟摆在走」，返唱只落在协和类低音上。D 让 G 多走一拍，再给 C，返唱最低声部的张力从 B 的 26.7% 减成 13.3%，全曲保留约 3%。压迫在听者已经认识的那个 A♭ 上发生；女高没换音，改变发生在她脚下。这是本轮结构取舍，下一轮优先用真人或更贴近真人的女高核对元音、气口和 m11 的咬合。

## 复现

从仓库根目录运行 `python tools/music/theme_studies.py --render`（Python 3.10+、NumPy、SciPy、FFmpeg）。MusicXML 可用 MuseScore 的 `-o <output.pdf> <input.musicxml>` 制谱；本次总谱均已导入制谱、渲染检查。只做小节或编配实验时，用 `--out .runtime/main-theme/another-pass` 保存隔离版本。
