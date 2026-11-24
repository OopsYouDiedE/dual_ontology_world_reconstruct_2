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
