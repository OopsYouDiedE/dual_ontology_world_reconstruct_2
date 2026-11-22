# 政策子集、Fuel 与公平计量

所有评分席位提交同一形式的 Python 源码；不存在用于竞赛得分的原生 Target 渠道。引擎只向政策提供量化观察数据，经过校验的 `actions` 返回固定步长裁判。健康度、动作进展及归因数据独立处于裁判侧。

```python
def decide(o, state):
    if state.get('room') != o['level']:
        state.clear()
        state['room'] = o['level']
    emit({'type': 'Wait'})
    for hit in o['rays'][9:18]:
        if isinstance(hit, dict) and hit['entity_id'] == 'latch':
            return {'type': 'Interact', 'target_entity_id': 'latch', 'op_type': 'latch'}
```

- 每个文件只定义函数；入口 `decide(o, state)`。支持循环、推导式、生成器、整数运算、条件、函数以及有界的文本、序列和映射。观察是私有数据副本；跨决策记忆通过 `state` 储存。
- 常用函数：`len`, `range`, `abs`, `min`, `max`, `sum`, `sorted`, `reversed`, `enumerate`, `zip`, `next`, `all`, `any`, `isinstance`, `int`, `str`, `bool`, `dict`, `list`, `tuple`, `set`。公共整数数学：`isqrt`, `sin`, `cos`, `dist2`, `match`。三角函数为百万分之一整数比例。可对数据使用 `get`, `items`, `keys`, `values`, `copy`, `append`, `extend`, `pop`, `clear`, `setdefault`, `add`, `update`, `split`, `removesuffix`；解释器按接收者类型筛选。复合下标更新写作 `state[key] = state.get(key, 0) + 1`。
- 语法验证禁止导入、文件/网络、反射、系统调用、时钟、异常捕获和对象类型定义。受控调用对数据形状、幂运算、调用深度、容器、哈希键与持久状态施加上界；集合按规范化数据顺序迭代。该执行域用于本地竞赛评测，外部陌生代码服务化部署时还应加操作系统权限与资源隔离。
- 普通决策 **60,000 Fuel**，进房首策 **300,000 Fuel**。每条政策字节码计 1；守卫调用另按容器大小、数据形状或遍历工作量扣费。宿主进入同一预算点时不读墙钟。Fuel 单位是确定性工作量，不能在不同 CPython 版本之间直接比较；正式运行记录实现、版本、源码和房间生成器的哈希。
- `emit(action)` 先做统一动作校验。返回字典或动作序列相当于最后一次 `emit`。永远使用已提交的最近一份合法动作；尚无候选则等待。达到上限或运行报错时，本轮 `state` 回滚，已提交合法候选继续有效。报表记录耗尽位置、已有候选数和拒收动作计数。
- `training` 与封卷后的 `batch` 使用同一编译、执行和计量。`batch` 对盲测席位另建独立政策实例重新求解，对比动作、Fuel 与每步状态链；随后用记录的动作流单独验证裁判重放。`UNRESOLVED_PLANNING_FAILURE` 仅用于遥测证据不足的失败。
