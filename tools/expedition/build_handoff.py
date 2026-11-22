"""Typeset the self-contained Chinese production handoff from project-owned evidence.
Requires reportlab, pypdf, and Microsoft YaHei (or HANDOFF_FONT and HANDOFF_BOLD).
"""
from pathlib import Path
import io, os, zipfile
from reportlab.pdfgen.canvas import Canvas
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase import pdfmetrics as fm
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle
from xml.sax.saxutils import escape
from pypdf import PdfReader,PdfWriter

root=Path(__file__).resolve().parents[2]; d=root/'docs/handoff/expedition'; e=d/'evidence'; tmp=root/'.runtime/expedition-pdf';tmp.mkdir(parents=True,exist_ok=True)
for n,p in [('body',os.getenv('HANDOFF_FONT','C:/Windows/Fonts/msyh.ttc')),('bold',os.getenv('HANDOFF_BOLD','C:/Windows/Fonts/msyhbd.ttc'))]:fm.registerFont(TTFont(n,p,subfontIndex=0))
W,H=A4; L=40; R=W-L; area=R-L; c=Canvas(str(tmp/'body.pdf'),pagesize=A4,pageCompression=1);c.setTitle('沉睡学院｜出征制作定稿');ink='#192C2B'; teal='#176D61'; quiet='#526764'; y=0; page=0
C=lambda s: colors.HexColor(s)
def label(x,yy,t,size=10,font='body',color=ink):
 c.setFillColor(C(color));c.setFont(font,size);c.drawString(x,yy,t)
def begin(k,title,sub):
 global y,page
 page+=1;c.setFillColor(C('#F8F8F3'));c.rect(0,0,W,H,fill=1,stroke=0);label(L,H-37,'THE SLEEPING ACADEMY    /    制作交接',9,'bold',teal);c.setStrokeColor(C('#AFBBB4'));c.line(L,H-48,R,H-48);label(L,H-80,k,10,'bold',teal);label(L,H-119,title,24,'bold');y=H-141;para(sub,11,17,quiet);y-=5

def para(t,sz=11.5,leading=18,col=ink,indent=0):
 global y
 sty=ParagraphStyle('p',fontName='body',fontSize=sz,leading=leading,textColor=C(col),wordWrap='CJK',splitLongWords=1);p=Paragraph(escape(t),sty);_,h=p.wrap(area-indent,1000);y-=h;p.drawOn(c,L+indent,y);y-=5

def block(t,b):
 global y
 y-=4;label(L,y-13,t,13,'bold',teal);y-=21;para(b)

def photos(pairs):
 global y
 gap=12;w=(area-gap*(len(pairs)-1))/len(pairs);h=w*2/3
 for i,(p,cap) in enumerate(pairs):
  x=L+i*(w+gap);c.drawImage(str(e/p),x,y-h,width=w,height=h);label(x,y-h-13,cap,8.3,'body',quiet)
 y-=h+25

def lines(rows):
 global y
 for a,b in rows:
  c.setStrokeColor(C('#D6DDD8'));c.line(L,y,R,y);y-=6;label(L,y-11,a,10,'bold',teal)
  para(b,10.5,16,indent=142);y-=1

def end():
 assert y>41,(page,y);c.setStrokeColor(C('#AFBBB4'));c.line(L,34,R,34);label(L,20,'織羽Oriha   ·   2026-11-22   ·   交付范围：桌面端正式出征',8,'body',quiet);label(R-19,20,f'{page:02}',9,'bold',teal);c.showPage()
begin('01   /   ENTRY','从哪里接手','唯一玩家入口：scenes/rogue/Run.tscn。按下开始，玩家先看到公共大厅；知道自己想带回什么，再决定走哪扇门。')
photos([('east/01-camp.jpg','01 / 公共大厅：招募、备装、查看路线。'),('east/02-chart.jpg','02 / 路线图：地标固定，岔路显示本次房间和掉落。')]);block('先查路径，再动工程','project.godot 指向 Run；FirstWatch.gd 管一局的状态，HouseMap.cs 发牌与连线，Crossing.gd 算机关后果。RogueRoomView.gd 把房卡落在原生地块上；GameControl.gd 通过真实窗口输入取证。');block('批准的制作路线','ArchBuilder 的组件目录统一调用生成器；角色沿编号模型加载。所有场景按显示分辨率输出。用大厅 04 的柔色阶、薄墨线与 SDFGI 校准正式房间，让廊柱、门楣和装置在低饱和背景上分得开。');block('怎样读这份交接','第 2 页定玩法，第 3 页交代推理与空间课，第 4 页记录参考选择，第 5–6 页给美术与资产合同，第 7–8 页列审核结果、门禁和文档树。附包内有逐文件路径、逐页审计、来源索引与实机状态 JSON，可离线检索。');end()
begin('02   /   EXPEDITION','同一座观测台，两种收据','营地 → 双列房位 → 双列房位 → 折返闸 → 双列房位 → 天文台。六层九个位置固定。种子从七张房卡中取六张，求解相邻层的合法连线；每局实际走三张。')
photos([('east/03-first-room.jpg','种子 1 / 第一站 Pump Archive，东侧给棘轮。'),('west/03-first-room.jpg','种子 2 / 第一站 Blind Switchboard，西侧给毛毡。')]);block('途中的东西决定最后怎样过','种子 1 先去泵房，再经退件室、折返闸及电报间。最终登记、安装棘轮、手摇晨钟：用 3 分钟完成这条通路，结算 6 箱。种子 2 取西路，经交换台、气闸、折返闸、暗房；用毛毡和封存手续敲钟，结算 8 箱。两局都剩 2 块毛毡、生命 9。');block('什么时候值得回去','开闸后可继续前进，或坐一次车回公共大厅，把生命恢复至 9、休整队伍，再从同一个闸续行。背包与已开机关随行；重复经过闸门没有第二份收益。营地 16 人自行活动，出征后由队长决定动作。');block('给空背包留一条路','同房最多消耗一个工具。棘轮省时间；毛毡在适用机关保住额外物资。空背包仍可登记、手动制动、手摇，慢通路用 18 分钟。当前时钟记录行动用时；关卡没有追击倒数。');end()
begin('03   /   PUZZLE LOGIC','玩家怎样学会一条规则','让一道门同时回答三个问题：我能走哪边？我从哪里知道这样做有用？过门会花掉什么？路径靠空间表示，推理靠可回查的线索，花费和收益写在决定之前。')
photos([('east/04-return-junction.jpg','折返闸：先解除封锁，再选继续或回营。'),('west/05-observatory.jpg','固定终局：装置位置稳定，背包改变操作顺序。')]);block('七张途中房卡的分工','退件室、交换台、泵房、升降机、气闸、暗房、电报间共用“读记录 → 选设备 → 看结果”的语法。岔路预告房名与掉落，玩家能绕开不熟的装置，也能为终局预留工具。种子改变遇见谁、先遇见谁；最终装置让玩家用熟悉的语法兑现准备。');block('上一轮的空间关卡怎样留下来','R2 要绕到同一铸件侧面，比较镜像中脊与双翼。R5 先隔着边界观察，再以试重验证。R7 要分批渡桥并由对岸接力；预警须从当时眼位看见。L03 用双视接桥：单人注视维持支撑，双人持续看同一段，第 41 步致死。共同保留“安全示范 → 只改一个条件 → 看到后果”的教法。');block('接入条件','这四个设计目前都在独立跑道。L03 的光学、几何和时序反例已通过；R5 与 R7 的证据和预警仍被评测拒绝。先修复证据链，再考虑加入正式房卡，避免把随机房做成首次进入就只能猜的机关。');end()
begin('04   /   FIELD STUDY','十四款参考，各取一个有用的动作','Sol 采了 18 段公开商店视频与 3 段连续实玩；194 张视频帧、13 张联系表，逐文件验证为 1080×720 JPEG。以下裁决来自看图后的选择；原始帧留本机，来源和时间戳随附。')
lines([('邪恶冥刻 / Inscryption','Notlad 01:02 路线、01:22 三件选项、01:27 指针切换、01:37 结算。采用“节点→对象→结果”，保留桌面空区；舍弃卡牌战斗。'),('Blue Prince','备用片 00:30 门前三选，00:42/48 门洞周边留空。把决定放在门前；沿用本游戏固定地标。'),('金偶像谜案 / 巴别塔圣歌','前者 00:10 现场、00:20/25 陈述；后者实玩 03:02–03:32 从拱门走向水渠，见到符号气泡。取线索出处与跨视角的亮面导向。'),('The Witness / TUNIC','面板旁线路（00:10）把规则接到门上；亮窗、楼板和暗梯（00:30）表达高差。取接点，不把全游戏改成面板；本批没拍到手册。'),('杀戮尖塔 / FTL','前者 00:15 分支、00:30 可跳过奖励，用来校准收益预告。后者实玩 01:38 投降报价与舱室状态同屏：玩家作选择时应仍能对照背包。'),('奥伯拉丁的回归','00:18 索具密线与 00:23 明甲板对照。把线留给门框和踏边，放弃全屏一位抖动。'),('Gloomwood / BELOW','前者以墙脚灯和长阶串起门，后者以窄入口、台阶和目的地光点指路。取连续地面边，保留本游戏第一人称尺度。'),('LIMBO / INSIDE','雾中梯横档和斜平台边缘保持可读；INSIDE 本批仅一张有效关卡画面。借剪影，不把操作点整体压黑。'),('Darkwood','00:03/23 俯视光扇揭示门槛。借局部亮区和门旁低线密，舍弃持续遮蔽通路的黑暗。')]);block('证据怎么用','三段连续窗口分别覆盖节点选择、跨视角行走、遇敌后的资源取舍。《巴别塔圣歌》的译词验证与 FTL 星图仍缺连续图证。其余商店片按字卡、场景展示和玩家操作分类；把选中的教法放回本项目岔路和折返闸验证。');end()
begin('05   /   ART DIRECTION','主风格选 04：柔色阶、薄线、间接光','四张大厅图来自同一机位，均关 Glow。看右侧柱础、远门和拱间暗面：它们决定玩家能否把地面边缘与装饰线分开。')
photos([('hall-01-continuous.jpg','01 连续受光：柱面细腻，远处端点较软。'),('hall-02-toon.jpg','02 柔色阶：柱面分明，接点仍偏软。')]);photos([('hall-03-toon-ink.jpg','03 加薄线：柱脚与墙角分开，远门仍平。'),('hall-04-toon-ink-sdfgi.jpg','04 再开 SDFGI：暗拱与亮门形成可读的纵深。')]);block('移进正式房间后怎么控制','桌面 Forward+、原分辨率 Lowpoly。墙地与服装共用柔光响应；深度／法线选择性描边，远处和亮灯减墨。战役线强 0.40，3D 饱和度 0.76，HUD 单独绘制。外窗处的 OmniLight3D 按时钟变化；室内灯与炉火按氛围。');para('复拍：营地可凭头肩轮廓区分人群，但侧光让部分衣服与投影相连。折返闸钟面清楚、上方偏暗。下次调局部补光和站位；不要为照亮天花而洗白钟面。',10,15);end()
begin('06   /   PRODUCTION','模型按它怎样改变来分类','ArchBuilder → Component Library → catalog.json → ComponentFactory。140 个目录项（线控 5、规则 39、装配 96）。保留挂点和旧场景 ID；分类决定编辑器真正调用的生成代码。')
lines([('线控  /  line','墙、栏杆、管路以点列为输入。墙高、厚度、门窗开口区间共同切网格与碰撞；扶手按间距布柱。管半径由 0.08 改 0.16 米，实测直径随之翻倍。改变折线也改变端口。'),('规则  /  rule','门窗按宽高，灯按吊距／杆长，梁按长和截面，柱按半径与高度；浑仪按半径建环。齿数同时改动渐开线轮形、轴心距及传动比。大厅专用门和灯保留原生成器，由同一目录登记。'),('装配  /  assembly','椅柜等物件以板件、支承与可复用部件组合。椅宽、座高、扶手开关按实例保存。门窗由规则生成，安装时才由装配器对齐墙洞；已挂装的根件先拆下再改尺寸。')]);block('角色与 Shader 的边界','正式角色走 HallWitnesses → Roster.attach → ImportedCharacter → UserModels/model_01…17.glb。06 是侦探，16 名居民用其余编号。17 个实际 mesh surface 都读到柔色阶系数 0.58，保留贴图与单双面分流。R-05 用于动作和光学试样，五套 fitted rig 保留为试装。');block('按用途放 Shader','scenes/components/rendering 下：surfaces 负责墙地与饰面及公共光响应；actors 负责人物；post 的 HallInk 只画结构断点；feedback 的 NightVeil 表达状态。水、玻璃和自发光仍用专用响应；接入同一个 3D 调色的最终视口。');block('怎么验证参数真的有用','在组件库改一个数，分别量网格、碰撞和接点；同配方再建一件，检查独立参数。31 项生产合同、55 项 ArchBuilder 检查通过；开发工作树另以 7 套布局核过 269 段墙碰撞、13 处门洞、21 次闸门动作。')
# Actual numbered characters on the same materials as the campaign.
w=177;h=w*2/3;c.drawImage(str(e/'numbered-roster-04.jpg'),L,y-h,width=w,height=h);label(L+w+12,y-24,'编号角色 · 生产材质核验',10,'bold',teal);label(L+w+12,y-44,'正式加载器实例化 17 人，逐 surface 读取实际材质。',9,'body',quiet);y-=h+5;end()
begin('07   /   AUDIT','前稿哪里写错，今天如何取证','旧 17 页逐页审核与 26 页纠错稿逐段复审均在附件。下表保留会误导下一位 AI 改错代码、选错角色或误判上线状态的问题。')
lines([('入口与关卡','原稿混列战役、十房评测、L 系展台；一张入口图也看不出视角接力。现用 Run 的真实输入与 L03 的专测分别取证，禁止把 R3 与 L03 混编号。'),('生产路径','旧 A/B/C 把生成来源、后期整理、运行装配混在一起。现按三种几何机制注册，用开洞射线、实例参数和真实 mesh 变化作验收。'),('照明与角色','旧稿把外窗局部灯写成方向光，把大厅参数和实机参数混用，也混记底模、试装与正式人物尺度。当前直接读取 Environment 与人物活动 surface。'),('路径与版本','文件存在不能说明发布包依赖它。原稿 64 个字面路径里 14 个仅本地；旧测试清单为按名筛选。当前分别登记索引与本地文件，从索引独立检出重建、截图。'),('历史计数','28 条是人工历史路线，2,564 项是消失文件；两种统计不互换。旧 Boot、Web、第一代 Run 与固定章节退出正式流程；原生 XML 和兼容 ID 仍在用。'),('成绩与风险','源码版本、种子、运行器、设备、动作与结算共同定位一次结果。十房 43 项仍有 5 失败、3 错误；R5 证据未成熟、R7 预警不可见。该专项独立于已走通的正式战役。')]);block('本次实测的边界','独立索引检出用 .NET 8 编译、全量导入，再跑种子、战役、生产、窗光、人物和 L03；两局实机为 RTX 3070 Forward+，原窗 1280×720，保存等比补边 JPG。导入 detective.gltf 报同名 lockpick 动作，当前编号角色与两局通关均成功。首次玩家辨路和运动帧时仍待测。');end()
begin('08   /   HANDOFF','只保留这一套工作流','先读根 README，按下表工作；附包用来查确切文件和争议来源。历史文档只作溯源，不能覆盖本页给出的现役入口。')
lines([('根目录','README.md：启动与玩家操作。AGENTS.md：项目维护约定。mcp/game/README.md：实机输入和观察。'),('建筑','tools/building_construction/production/README.zh-CN.md：三类生成、参数、开洞与装配。'),('docs/handoff/expedition/','README.md → expedition-handoff.pdf、render.md、reference-study.md。分别回答工作顺序、定稿、Shader／人物、逐款参考取舍。'),('目录内的索引','workflow-paths.tsv：接线、目录项生成器与测试；source-inventory.tsv：库内交付／本地路径快照。study-index/：视频来源、变体、逐帧哈希。'),('目录内的证据','evidence/east 与 west 各六张 JPG、一份 frames.json；同目录四档大厅和编号角色各有实图。verification.zip 收录执行日志。')]);block('先后跑什么','① dotnet build；② core/rogue_topology/tests 和 tools/expedition/route_test.gd：256 种子各跑两次得 246 种有序手牌、7 组边；③ tools/test/night_watch.gd：招募、三局实体过门、单次折返。');para('④ tools/expedition/viewport_run.py：--seed 1 --lane east 与 --seed 2 --lane west。每局从营地走到最后的晨钟。⑤ 改资产后跑 production_pipeline_test、building_candidate_unit、gear_check；改光照或人物跑 room_daylight 与 numbered_roster_test。完整命令在附包 README。');block('留给下一位 AI 的第一件事','请一位首次玩家在岔路说出想带回什么，再观察他会不会为终局留一件工具。若方向错，查地面与门；若理由错，查铭牌和手册；若成本错，查路线图和结算。这样才能分开画面、推理与数值三个问题。');end();c.save()
zipbuf=io.BytesIO()
with zipfile.ZipFile(zipbuf,'w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(d.rglob('*')):
  if p.is_file() and p.suffix.lower() not in ('.pdf','.jpg','.import') and p.name!='.gdignore':z.write(p,p.relative_to(d).as_posix())
 z.write(root/'tools/building_construction/production/README.zh-CN.md','building-production.md')
w=PdfWriter();w.append(PdfReader(tmp/'body.pdf'));w.add_metadata({'/Title':'沉睡学院｜出征制作定稿','/Author':'織羽Oriha'});w.add_attachment('expedition-evidence.zip',zipbuf.getvalue());w.write(d/'expedition-handoff.pdf')
