# 第一远征：配对人工偏好评估

用 Python 标准库训练一个小型三结果模型，并分别验证它对新受试者、新结构家族的预测。上一轮 Human Sol 的路径、停驻和通行时间继续作为结构诊断，标签表仅接收实际人类评价。

## 采集与输入

1. 预先确定一个问题，例如“两段都体验过后，你更愿意再玩哪一个布局？”明确允许 `tie`（体验后无偏好）；未完成、跳过和技术故障留作缺失。每对使用一致的展示条件和体验时长，随机或平衡呈现顺序，隐藏设计假设。`A` / `B` 按当次表中的 `layout_a` / `layout_b` 记录。
2. 每位真人生成一个随机代号，研究内复用：`python -B -c "import secrets; print('p_'+secrets.token_hex(8))"`。评价表只收代号与选择；姓名、联系信息和身份映射留在表外。代号用于分组，训练特征与输出都不含代号。细分折指标留作内部诊断，小样本对外优先汇报聚合结果。
3. `labels.empty.csv` 只有表头。每行是一位真人对一个 `trial_id` 的选择，`source` 由采集者填写 `human`；脚本验证字段，真人来源由采集者负责。相同试次可以由多位受试者评价，展示顺序可交换，但始终指同一无序布局对。每位受试者每试次限一次。
4. `layouts.empty.json` 定义特征顺序。向 `layouts` 加入 `布局ID: {"family": "结构家族ID", "x": [数值, ...]}`。先固定特征与缩放，每项在 `[-1,1]`，可用开口偏移等可测属性。每个布局只归一个家族，同一对的两端归同一族。把共享原型、同一场景改版和复用的对照布局归在同一族；收集真正独立的另一族，才可做结构验证。现有 A1 原版/偏置门洞属于同一族，换种子仍是同一族。

## 运行

从仓库根目录运行。真实标签和结果放在受控的本机数据目录；例如仓库忽略的 `.runtime/structure-preference/`，不要提交。

```powershell
$p = 'docs/production/expedition-01/playtest/preference'
python -B "$p/test_preference.py" -v
python -B "$p/evaluate.py" --layouts "$p/layouts.empty.json" --labels "$p/labels.empty.csv"
# 收集完真人标签后：
python -B "$p/evaluate.py" --layouts .runtime/structure-preference/layouts.json --labels .runtime/structure-preference/human.csv
```

空表退出 2，错误信息走 stderr，stdout 为空；来源混入非真人行或两种留出任一不足两组也拒绝报告。自测使用进程内数学夹具和空模板，只输出测试结果。

## 模型与验证依据

- Bradley & Terry (1952), *Rank Analysis of Incomplete Block Designs: The Method of Paired Comparisons*, **Biometrika** 39, 324–345，DOI `10.1093/biomet/39.3-4.324`。成对胜率用相对强度表达。
- Davidson (1970), *On Extending the Bradley-Terry Model to Accommodate Ties in Paired Comparison Experiments*, **JASA** 65, 317–328，DOI `10.1080/01621459.1970.10481082`。平局质量与两者强度的几何平均成比例。这里令布局强度为 `exp(w·x)`，三项概率由 `softmax([d/2, -d/2, log_tie])` 给出，其中 `d = w·(x_A−x_B)`。交换 A/B 就交换两个胜率，平局率保持。每折用训练部分最小化平均负对数似然，加固定 L2 惩罚 `0.1/2 × ||θ||²`；特征化参数和惩罚是本工具的实现选择。
- Roberts et al. (2017), *Cross-validation strategies for data with temporal, spatial, hierarchical, or phylogenetic structure*, **Ecography** 40, 913–929，DOI `10.1111/ecog.02881`。按依赖单位切块：一套逐受试者留出，一套逐结构家族留出。前者测试同类结构上的新受试者，后者允许受试者跨折、测试新结构；两套结果各自解读。推荐让多位受试者交叉评价多个家族，减少受试者与家族重合造成的混淆。

每折报告测试集三分类 log loss（越低越好），以及同折训练的平局率基线（A/B 等概率，平局参数可学习）；按留出组等权汇总。全量拟合权重单独列出，用于后续预测。最少两组只是运行下限；正式比较应收集更多独立家族和真人评价。模型学习的是题目所问的配对选择倾向。

## 持续筛选台（个人设计判断）

这条队列按题目分别拟合既有三结果模型。建筑题的两维依次为「保留中轴、引导光集中在沿途」，陈设题为「功能编组、工位同侧」；`dx` 为预先声明的左右特征差，复合对照的结果保留在本题语境里。左右位置目前固定，发现的倾向须在换位的新对照中复验。个人审美与多受试者模型分别报告。

- 本机 `.runtime/design-review/review-votes.sqlite3` 保存展示内容、素材 SHA-256、投票前的三项概率、只学平局率的基线预测、选择、理由和时间。历史聊天用 `import-prior` 导入，不补写事前预测；跳过不作标签。选新对时先覆盖不同设计变化，再优先展示预测分歧大的对照。工房有验收报告的必须先过对应 `ok` 门槛。
- 拱廊和工房的第二轮用 `structure/round02.py`、`clutter/round_02.py --seed 31 --seed 113 --seed 211` 生成。本机 `inbox/*.json` 可继续投放与 `rounds.json` 同结构的清单；新变体使用新 ID、独立素材文件，保持已展示材料不变。
- 每个维度分别验收：模型已见过本维度样本后，第一次遇到独立新家族时冻结预测。暂定至少 6 个此类真人判断、至少 80% 的新家族给真实选择的概率高于基线、平均 log loss 也优于基线，才进入影子试用（人工仍裁决）。这是项目试用门槛，后续应检查失败案例、位置偏差与更多家族。相同原型换种子或变照明均归原家族。

```powershell
$p='docs/production/expedition-01/playtest/preference'
python -B "$p/serve_queue.py"  # 本机 127.0.0.1:18764
# CLI 也可接收用户在聊天里的明确选择；先 next，再 vote。
python -B "$p/queue_review.py" next
python -B "$p/queue_review.py" status
```

### 证据返工与再次放映

「看不清差别」记为 `unclear`，「两版都要返工」记为 `rework`。两种回答分别计数，均不参与偏好拟合、预测损失或新家族检验；它们暂停同一 scope/family/contrast/edition 的未判卡。`skip` 保持原义，旧记录不补填动机。重新拍摄用新的卡号、文件名和 edition。历史记录可回看原片。

第三轮录像的发布分两步：先在实际视口核查入口全景、走近时的共同路线和近景差异，并记录控制变量；再运行 `approve_film.py arcade|room --entry ... --approach ... --detail ... --controls ...` 签出带录像 SHA-256 的本地验收文件。放映台只有在 `gate` 存在、验收通过且录像摘要匹配时才会出题。编码与分辨率可由 ffprobe 核对；美术可读性由检查者看画面决定。不要覆盖已开题的文件。
