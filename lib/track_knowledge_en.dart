/// English for the static track-knowledge copy. Keys are the Chinese
/// source strings. Missing keys fall back to Chinese so nothing is blank.
const Map<String, String> knowledgeEn = {
  '赛道旗语': 'Flags',
  '看懂旗语再上赛道': 'Read the flags before you go out',
  '旗语怎么看': 'How to read flags',
  '旗语是赛道上的语言，看不懂旗就等于闭着眼睛开车。':
      'Flags are the language of the track. Missing one is driving blind.',
  '谁挥旗：赛道边的裁判哨（marshal post）负责挥旗，灯光面板与旗语含义相同；正赛另有赛会控制的信号。':
      'Who waves them: marshal posts beside the track. Light panels mean the same thing. A race may also use race-control signals.',
  '看到旗先减速、再理解：黄旗区禁超车；红旗停赛；方格旗结束。先做对动作，再想为什么。':
      'Slow down first, then interpret: no passing under yellow; red stops the session; the checkered flag ends it. Do the right thing, then ask why.',
  '规则来源：汽车旗语以 FIA《国际运动规则》附录 H 为准，摩托以 FIM 大奖赛规则为准；赛道日沿用同一套旗语，但具体执行以当日简报为准。':
      'Source: car flags follow FIA International Sporting Code Appendix H; bikes follow the FIM Grand Prix rules. Track days use the same flags. That day’s briefing decides how they are applied.',
  '未核实：国内各赛道日的旗语细节可能有本地调整，出场前务必听简报。':
      'Unverified: local track days may adjust details. Listen to the briefing before you go out.',
  '危险与状态旗': 'Hazard and status flags',
  '绿、黄、红、白、黄红条纹——告诉你赛道前方发生了什么。':
      'Green, yellow, red, white, and yellow-red stripes tell you what is ahead.',
  '绿旗：前方畅通，可恢复正常速度与超车；常出现在黄旗区之后。':
      'Green: the track ahead is clear. Resume speed and passing. Often shown after a yellow sector.',
  '单黄旗（挥动）：前方路边或路上有危险，减速、禁超车、准备变线。':
      'Single yellow (waved): a hazard at the side or on the track. Slow down, no passing, be ready to change line.',
  '双黄旗（两面同挥）：危险更严重，可能部分或全部堵塞赛道，或有工作人员在赛道上；大幅减速、禁超车、准备停车。':
      'Double yellow (both waved): a worse hazard. The track may be partly or fully blocked, or marshals may be on it. Slow a lot, no passing, be ready to stop.',
  '红旗：比赛/练习中断，所有人减速、不超车、按指示缓慢回维修区（赛道日按简报程序回场）。':
      'Red: the session is stopped. Everyone slows, no passing, and returns to the pits as directed (track days follow the briefing).',
  '白旗：前方有慢车（如救援车或速度很慢的车辆）。':
      'White: a slow vehicle ahead, such as a recovery vehicle or a very slow car.',
  '黄红条纹旗（静止展示）：路面抓地力下降，通常是油渍或水渍；本身不是禁超车区，但要小心。':
      'Yellow-red stripes (held still): less grip, usually oil or water. Not a no-passing zone by itself. Be careful.',
  '尺寸参考：FIA 规定方格旗与红旗不小于 80×100cm，其余旗不小于 60×80cm（来源：Aston Martin F1 规则解读，引自 FIA 附录 H）。':
      'Size note: FIA says the checkered and red flags are at least 80×100 cm; other flags at least 60×80 cm (Aston Martin F1 rules guide, citing Appendix H).',
  '指令旗：蓝旗、黑旗与方格旗': 'Instruction flags: blue, black, checkered',
  '这几面旗是点名道姓的，看到自己的号码就要行动。':
      'These flags name you. If your number is on one, act.',
  '蓝旗：后方有更快的车要超车；练习中让行，正赛中被套圈时须在最早机会让过；出维修区时蓝旗表示主赛道有来车。':
      'Blue: a faster car is behind. In practice, let it by. In a race, a lapped car must yield at the first chance. At pit exit, blue means traffic is on the track.',
  '黑旗（配车号）：该车手被取消资格，下一圈进站、比赛结束。':
      'Black (with a number): that driver is disqualified. Pit next lap. The race is over for them.',
  '黑旗 + 橙色圆点（肉丸旗，配车号）：车辆有机械故障、可能危及自己或他人，须尽快进站检修，修好并经检查后方可继续。':
      'Black with an orange disc (meatball, with a number): a mechanical problem that may endanger you or others. Pit as soon as you can. Continue only after it is fixed and checked.',
  '黑白对角旗：对不规范驾驶行为的警告，仅出示一次；再犯将受罚。':
      'Black-and-white diagonal: a warning for unsportsmanlike driving, shown once. A repeat is penalized.',
  '方格旗：练习或比赛结束，挥动至所有车辆通过终点线；此后减速、完成冷却圈、回维修区。':
      'Checkered: practice or the race is over. It is waved until every car has passed the line. Then slow down, do a cool-down lap, and return to the pits.',
  '汽摩差异：MotoGP 另有白底红斜十字旗（该路段下雨）与纯白旗（允许换车，即 flag-to-flag）；F1 的白旗仅表示前方慢车。赛道日一般不使用换车规则。':
      'Car vs bike: MotoGP also uses a white flag with a red cross (rain in that sector) and a plain white flag (bike change allowed, flag-to-flag). In F1, white only means a slow vehicle ahead. Track days usually do not use a bike-change rule.',
  '安全与礼仪': 'Safety and manners',
  '赛道日不是比赛，先把规矩放心上': 'A track day is not a race. Learn the rules first',
  '赛道日不是比赛': 'A track day is not a race',
  '先把心态放对，赛道日是练车，不是争冠。':
      'Set the mindset first. A track day is practice, not a championship.',
  '非竞赛活动：赛道日没有奖杯与排名；危险驾驶会被请出场且不退款（多家主办方规则）。':
      'Not a competition: no trophies or standings. Dangerous driving can get you sent home with no refund (common organizer rules).',
  '分组：车辆按经验分组（新手/中级/高级），或开放维修区自由进出；新手日通常有教练带队与定速熟悉圈。':
      'Groups: cars are split by experience (novice / intermediate / advanced), or the pits are open. Novice days often have an instructor and a set-speed sighting lap.',
  '强制简报：每天开场有安全简报，必须参加；旗语、超车区与维修区规则都在简报里讲。':
      'Mandatory briefing: every day starts with a safety briefing you must attend. Flags, passing zones, and pit rules are covered there.',
  '暖胎圈与冷却圈：第一圈是暖胎暖刹圈，慢速跑；最后一圈是冷却圈，给刹车降温后再进站。':
      'Out lap and cool-down: the first lap warms tires and brakes, so go slowly. The last lap cools the brakes before you pit.',
  '超车礼仪': 'Passing manners',
  '超车要对方邀请，慢车不堵路，快车不催命。':
      'Pass only when invited. Slow cars do not block. Fast cars do not force it.',
  '只在指定超车区、且拿到前车示意（point-by）后才能超车；前车伸左手出窗指向要让的一侧。':
      'Pass only in the designated zone, and only after a point-by. The car ahead puts the left hand out and points to the side you should use.',
  '每个后车都需要单独的示意，前车让了一辆不等于让了所有车；不确定就别超。':
      'Each car behind needs its own point-by. Letting one by does not let everyone by. If you are unsure, do not pass.',
  '弯中不超车；被超的车保持走线、松油或轻点刹车配合，不要突然变线。':
      'Do not pass in the corner. The car being passed holds its line and lifts or brakes lightly. Do not swerve.',
  '常看后视镜：后车贴上来说明它更快，在下一个超车区让过去；车队排起来了就先进站、隔一会儿再出。':
      'Check the mirrors. A car closing on you is faster. Let it by at the next passing zone. If a train forms, pit and come out later.',
  '摩托：可左右两侧超车，但须留足空间；入弯前与出弯加速时可超，车手入弯点与弯中不超；前车永远有优先权，超车责任在后车（MSV 规则）。':
      'Bikes: you may pass on either side, with room. Pass before the corner or on exit, not at the turn-in or mid-corner. The rider ahead has priority. The passer owns the risk (MSV rules).',
  '维修区、失控与故障处理': 'Pits, spins, and breakdowns',
  '出事时先保人，再保车；慌乱是最危险的操作。':
      'If something goes wrong, protect the person first, then the car. Panic is the dangerous move.',
  '维修区限速：各赛道与主办方不同，以当日简报为准（常见约 15–20 英里/时，即 25–30 公里/时上下；F1 正赛维修区限速 80 公里/时、摩纳哥 60 公里/时——仅供参考，赛道日不适用该数字）。':
      'Pit speed: it varies by track and organizer. Use that day’s briefing (often about 15–20 mph, roughly 25–30 km/h). F1 race pit limits are 80 km/h, Monaco 60 km/h — reference only, not a track-day number.',
  '打滑/失控：双脚踩死（刹车 + 离合），双手握紧方向盘，别乱打方向；停稳后再看情况。':
      'A slide or spin: both feet in (brake and clutch), both hands on the wheel, do not saw at it. Look around only after you have stopped.',
  '冲出赛道：先减速、直线开出缓冲带；确认安全后再缓慢回赛道，不要高速斜切回来（容易再次失控甚至翻车）；留意最近裁判哨的指示，必要时向赛事干事报告。':
      'Off track: slow down and drive straight into the runoff. Rejoin slowly only when it is safe. Do not cut back at speed (easy to lose it again or roll). Watch the nearest marshal, and tell an official if needed.',
  '车辆故障：开出走线、打手势示意减速，尽量把车停到安全处；无法行驶时留在车内等工作人员（摩托：人离开车辆、站到护墙后）。':
      'A failure: leave the racing line, signal that you are slowing, and stop somewhere safe. If you cannot move, stay in the car and wait (bikes: get off and stand behind the barrier).',
  '赛道上绝不逆行、绝不倒车；维修区内无指示不得倒车。':
      'Never drive the wrong way or reverse on track. Do not reverse in the pits unless told to.',
  '驾驶技术': 'Driving',
  '走线、刹车与平顺': 'Line, braking, and smoothness',
  '走线基础': 'The basic line',
  '走线就是用全场宽度把弯“拉直”，外-内-外是最短的路。':
      'The line uses the full width to straighten the corner. Outside-inside-outside is the short way around.',
  '基本走线：外侧进弯、切内侧弯心（apex）、再回到外侧出弯；用满赛道宽度，弯就变得更缓、能带更高速度。':
      'Basic line: enter from the outside, clip the inside apex, and exit back to the outside. Using the width makes the corner gentler and faster.',
  '弯心位置决定出弯：弯心越晚，出弯时车身越早回正、越早全油门。':
      'Apex placement sets the exit. A later apex lets the car straighten sooner and get to full throttle sooner.',
  '常见新手错误是弯心过早：提前切入内侧，出弯时路不够用、方向盘还打着，只能收油。':
      'A common novice error is an early apex: you turn in too soon, run out of road on exit, and still have steering lock on, so you have to lift.',
  '原则：接大直道的弯用晚弯心（牺牲一点入弯速度换出弯速度）；接刹车区的弯可用偏几何弯心、多带速度。':
      'Rule of thumb: a corner onto a long straight wants a late apex (give up a little entry speed for exit speed). A corner into a braking zone can use a more geometric apex and carry more speed.',
  '到新赛道先从出弯反推：找到出弯点，再定弯心与入弯点；刹车点用固定参照物（刹车牌、标志物）。':
      'On a new track, work backward from the exit: find the exit, then the apex and the turn-in. Use a fixed marker for the braking point.',
  '刹车技术': 'Braking',
  '刹车不是踩死就行，目标是贴着极限减速、又不锁死。':
      'Braking is not just standing on the pedal. The aim is to slow at the limit without locking up.',
  '阈值刹车（threshold braking）：在直线上把刹车踩到轮胎附着极限、刚好不触发 ABS 或锁死，获得最短刹车距离；新手先从早刹车开始，逐步延后刹车点。':
      'Threshold braking: on the straight, brake at the tire’s limit, just short of ABS or lockup, for the shortest stop. Novices start early and move the point back.',
  '刹车要“快踩、稳住、顺放”：先快速建立压力，再根据速度线性松开；突然松刹车会让车头上抬、失去前轮抓地。':
      'Brake “on quickly, hold, release smoothly”: build pressure fast, then ease off in line with speed. A sudden release lifts the nose and unloads the front tires.',
  '视线：刹车时眼睛看向弯心与出弯点，不要盯着车头前方。':
      'Vision: while braking, look at the apex and the exit, not at the nose of the car.',
  '循迹刹车（trail braking，进阶）：入弯时带一点刹车、边刹边转，保持前轮载荷、帮助车头转向；属于进阶技术，新手先练好直线刹车再尝试，且只在赛道上练。':
      'Trail braking (advanced): carry a little brake into the corner, braking as you turn, to keep load on the front and help it rotate. Learn straight-line braking first, and practice it only on track.',
  '重量转移与平顺': 'Weight transfer and smoothness',
  '刹车、油门、方向盘都在搬运车身重量，动作越顺越快。':
      'Brake, throttle, and steering all move the car’s weight. Smoother is faster.',
  '刹车时重量移向前轮（前轮抓地多、后轮少）；加速时重量移向后轮；转向时重量移向外侧轮胎。':
      'Braking moves weight to the front (more front grip, less rear). Accelerating moves it rearward. Steering moves it to the outside tires.',
  '每条轮胎的抓地力有上限：刹车、转向、加速共用这 100%——刹车踩得越重，能用来转向的抓地就越少。':
      'Each tire has a grip limit. Braking, turning, and accelerating share that 100%. The harder you brake, the less grip is left for steering.',
  '入弯前要在直线上完成大部分减速；弯中突然收油或急刹都会打破平衡，引发推头或甩尾。':
      'Do most of the slowing on the straight before turn-in. A sudden lift or stab of brake mid-corner upsets the car and can cause understeer or a spin.',
  '平顺是速度的前提：所有操作（刹车、转向、油门）都要渐进，别“砸”踏板、别“扔”方向盘。':
      'Smoothness comes before speed. Brake, steer, and throttle progressively. Do not stab the pedals or throw the wheel.',
  '摩托专项': 'Motorcycle specifics',
  '压弯、反向转向与装备': 'Body position, counter-steering, and gear',
  '压弯姿势': 'Cornering position',
  '身体先动，车再动；姿势对了，车就不用压那么低。':
      'Move your body first, then the bike. A good position means the bike does not have to lean as far.',
  '基础：脚掌踩脚踏、脚跟内扣；入弯前把身体移到弯内侧——半边屁股出座、内侧肩膀下沉、外侧大腿夹住油箱承重。':
      'Basics: balls of the feet on the pegs, heels in. Before the corner, move to the inside — one cheek off the seat, inside shoulder down, outside thigh gripping the tank.',
  '上下半身同等幅度向内移，背部与车身中线基本平行、向内偏移；手臂放松微屈，别用手臂撑体重。':
      'Move the upper and lower body inward together. Keep the back roughly parallel to the bike’s centerline, shifted inside. Arms relaxed and slightly bent. Do not hold your weight on your arms.',
  '同样速度与弯道半径下，身体挂出去能让车身更直立，留出更多轮胎接地面积与倾角余量；也可反过来用同样倾角跑更快。':
      'At the same speed and radius, hanging off lets the bike stay more upright, with more tire contact and lean in reserve. Or you can use the same lean and go faster.',
  '姿势要在刹车前就摆好，不要在入弯瞬间才挪身体；出弯时用腿脚把身体带回，不要只用手臂拉。':
      'Get into position before you brake, not at the moment of turn-in. On exit, use your legs to come back to center, not just your arms.',
  '新手不必追求磨膝：姿势正确、速度循序渐进，膝盖自然会接近地面。':
      'Novices do not need to chase a knee slider. With a correct position and a gradual pace, the knee gets closer on its own.',
  '反向转向': 'Counter-steering',
  '想向右转，先向左推一把——这不是技巧，是物理。':
      'To turn right, press the left bar forward — that is physics, not a trick.',
  '速度起来后，摩托只能靠反向转向（counter-steering）准确入弯：向右转就向前推右手把（或向后拉左手把），车身随之向右倾倒。':
      'Once you are moving, a bike turns accurately by counter-steering: to go right, push the right bar forward (or pull the left bar back). The bike leans right.',
  '推得越快越果断，车身倾倒越快；只靠压身体、蹬脚踏转向是不够精确的，不能替代反向转向。':
      'A quicker, firmer push leans the bike faster. Body weight and peg pressure alone are not precise enough to replace counter-steering.',
  '练习方法：直线行驶中轻推一侧手把，感受车身向同侧倾倒；先在空旷处低速体会，再上赛道用。':
      'Practice: on a straight, press one bar lightly and feel the bike lean that way. Learn it in an open area at low speed, then use it on track.',
  '入弯点到了才推把；推把同时视线看向出弯点，身体跟随即可。':
      'Press the bar when you reach the turn-in. Look at the exit as you press, and let your body follow.',
  '摩托装备与雨天': 'Bike gear and rain',
  '装备是底线，雨天是另一套开法。':
      'Gear is the minimum. Rain is a different way of riding.',
  '头盔：赛道日一般要求全盔；欧洲现行标准为 ECE 22.06（2020 年发布、取代 22.05，新增旋转冲击测试）；FIM 国际赛事自 2026 年起强制 FRHPhe-02 认证（须先通过 ECE 22.06 等基础标准）。头盔摔过、超期或破损即报废。':
      'Helmet: track days generally require a full-face. The current European standard is ECE 22.06 (published 2020, replacing 22.05, with a rotational-impact test). FIM international events require FRHPhe-02 from 2026 (which itself requires ECE 22.06 or equivalent). A helmet that has been crashed, is expired, or is damaged is scrap.',
  '皮衣：连体皮衣或 360° 拉链连接的分体皮衣；多数赛道不接受纺织骑行服。另需手套、过踝靴子、护背。':
      'Leathers: a one-piece, or a two-piece joined by a 360° zipper. Most tracks do not accept textile riding gear. You also need gloves, over-ankle boots, and a back protector.',
  '车辆：多数赛道要求前刹车拉杆护弓（防摔车时误触刹车），大灯/后视镜贴掉或拆除，通过噪音测试（限值各赛道不同，以赛事公告为准，如 MSV 部分场次静态 102–105 dB）。':
      'The bike: most tracks require a front brake-lever guard (so a fall does not pull the brake). Tape or remove lights and mirrors, and pass the noise test (limits differ; use the event notice. Some MSV sessions use a static 102–105 dB).',
  '雨天：所有操作更柔和——更早更轻地刹车、更晚更缓地开油、减少倾角、用更偏几何的走线；湿滑路面抓地力低，别在雨天练极限。':
      'Rain: do everything more gently — brake earlier and lighter, open the throttle later and slower, use less lean, and a more geometric line. Wet grip is low. Do not chase the limit in the rain.',
  '汽车专项': 'Car specifics',
  '坐姿、跟趾与胎压': 'Seating, heel-and-toe, and tire pressure',
  '坐姿与手位': 'Seat and hands',
  '坐不对，方向盘和踏板都使不上劲。':
      'A bad seat means you cannot use the wheel or the pedals properly.',
  '坐进座椅而不是坐在上面：臀部与腰部顶住椅背，左脚踩死踏板固定身体。':
      'Sit in the seat, not on it: hips and lower back against the backrest, left foot braced on the dead pedal.',
  '调整前后距离：手臂伸直时手腕能搭在方向盘顶端，握盘时手肘自然微屈；膝盖微屈、能把踏板踩到底。':
      'Set the distance: with arms straight, the wrists rest on the top of the wheel; gripping it, the elbows are slightly bent. Knees slightly bent, and you can push the pedals to the floor.',
  '靠背较直，不要半躺；肩膀贴住椅背、头部端正，别随弯“歪头”。':
      'Keep the backrest fairly upright, not reclined. Shoulders against the seat, head level. Do not lean your head into the corner.',
  '手位：双手 9 点与 3 点位置，拇指搭在方向盘内侧；小修正用手腕，别双手交叉打轮（手对手交替送轮）。':
      'Hands at 9 and 3, thumbs inside the rim. Small corrections come from the wrists. Do not cross your arms (shuffle the wheel hand to hand).',
  '车内清空杂物：松散物品在刹车时会变成抛射物；赛前清空手套箱、门兜与后备箱杂物。':
      'Clear the cabin: loose objects become missiles under braking. Empty the glovebox, door pockets, and trunk clutter before the day.',
  '跟趾与降挡': 'Heel-and-toe and downshifts',
  '降挡时补一脚油，让转速跟上车速，车才不会点头。':
      'Blip on the downshift so revs match road speed and the car does not nod.',
  '跟趾（heel-and-toe）：右脚掌踩刹车的同时，用脚掌外侧轻点油门补转速，左脚踩离合降挡；目的是降挡后转速匹配、避免后轮拖拽与车身点头。':
      'Heel-and-toe: the ball of the right foot stays on the brake while the outside of the foot blips the throttle, and the left foot clutches for the downshift. The revs match so the rear tires are not dragged and the car does not nod.',
  '现代踏板布局多用“脚掌 + 脚侧”而非真的脚跟，名字是历史沿用。':
      'Modern pedals usually use the ball of the foot plus the side of the foot, not a literal heel. The name is historical.',
  '适用：手动挡降挡入弯；自动挡/拨片车不需要。先练熟刹车与走线再练跟趾，别在快弯里分心练。':
      'Use it on a manual downshift into a corner. Automatics and paddle-shift cars do not need it. Learn braking and the line before heel-and-toe, and do not practice it in a fast corner.',
  '轮胎胎压': 'Tire pressure',
  '没有放之四海皆准的赛道胎压，起点永远是厂家建议值。':
      'There is no universal track pressure. Start from the maker’s recommended cold pressure.',
  '轮胎跑热后胎压会上升，冷胎压设得太高、热胎后会过高；先按车辆/轮胎厂家的冷胎压建议值起步。':
      'Pressure rises as the tire heats. A cold pressure that is already high will be too high when hot. Start from the vehicle or tire maker’s cold-pressure figure.',
  '每节结束后测热胎压、记录变化，下节据此微调；不同车型、轮胎与赛道温差都不同，具体数值问现场教练或有经验的车友。':
      'After each session, measure hot pressure and note the change, then adjust the next session. Cars, tires, and track temperatures differ. Ask a coach or an experienced driver for a number.',
  '检查胎面：胎肩磨损过度、胎面起皮或鼓包都要处理；胎压表是赛道日必备工具之一。':
      'Check the tread: excess shoulder wear, peeling, or a bulge needs attention. A pressure gauge belongs in the track-day kit.',
  '未核实：本库不提供具体胎压数值；任何“某车型统一打 XX”的说法请以厂家与现场实测为准。':
      'Unverified: this library does not give a pressure number. Any “this car always runs XX” claim should be checked against the maker and a measurement on the day.',
  '规则': 'Rules',
  '赛道日与正式比赛的规则': 'Track-day rules and race rules',
  '赛道日与正式比赛的区别': 'Track day vs a race',
  '赛道日学规则意识，正式比赛才有规则执行。':
      'A track day teaches rule awareness. A race is where the rules are enforced.',
  '赛道日：主办方定规则（分组、超车区、噪音、装备），现场裁判与教练执行，违规一般是警告或请出场；没有积分与排名。':
      'Track day: the organizer sets the rules (groups, passing zones, noise, gear). Marshals and instructors apply them. A breach is usually a warning or being sent home. There are no points or standings.',
  '正式比赛：按 FIA《国际运动规则》与各赛事运动规则执行，由赛事干事（stewards）裁决，可罚时、罚位、取消成绩。':
      'A race: the FIA International Sporting Code and that series’ sporting regulations apply. Stewards decide. Penalties can be time, grid places, or exclusion.',
  '旗语同一套，但正赛多了黑旗家族、罚时等竞赛处罚；赛道日极少用黑旗罚人，更多用旗语管安全。':
      'The flags are the same set, but a race adds the black-flag family and time penalties. Track days rarely black-flag someone. Flags there are mostly for safety.',
  '无论哪种场合，简报与赛事公告是最终依据；规则每年可能修订。':
      'In either setting, the briefing and the event bulletin are the final word. Rules can change each year.',
  '安全车、虚拟安全车与红旗': 'Safety car, virtual safety car, and red flag',
  '三档减速手段，强度不同、用法不同。':
      'Three ways to slow the field. Different strength, different use.',
  '虚拟安全车（VSC）：无实体车，全场按 FIA 设定的最小时限（delta）减速；车与车之间的差距基本保留；维修区只允许进站换胎（F1 规则）。':
      'Virtual safety car (VSC): no physical car. Everyone slows to an FIA minimum time (delta). Gaps between cars are mostly kept. Under F1 rules, a pit stop may only change tires.',
  '安全车（SC）：实体安全车带队，全场排成一列跟在其后、差距清零；不得超车；进站同样只限换胎（F1 规则，特殊情况除外）。':
      'Safety car (SC): a real car leads. The field bunches up behind it and gaps are wiped. No passing. Under F1 rules a stop is tires only, except special cases.',
  '红旗：比赛/练习暂停，所有人减速、不超车、按指示回维修区或指定地点；恢复时按赛会程序重新发车或继续。':
      'Red flag: the session is suspended. Everyone slows, no passing, and goes to the pits or the place they are told. Restart or continuation follows race control.',
  '选择逻辑：危险较小、处理快用 VSC；需要近距离保护工作人员用 SC；赛道无法安全通行用红旗。':
      'Which one: a smaller, quick hazard uses the VSC; marshals who need a car nearby use the SC; a track that cannot be driven safely uses red.',
  '未核实：摩托比赛也有安全车程序，但 MotoGP 更常用红旗中断与重开，各级别执行细节以 FIM 当年规则为准。':
      'Unverified: bike racing also has a safety-car procedure, but MotoGP more often stops and restarts under red. Details follow that year’s FIM rules.',
  '处罚种类': 'Penalties',
  '罚则从轻到重，知道红线在哪就别去碰。':
      'Penalties run from light to heavy. Know the line and stay off it.',
  '轻：警告/训诫，记入车手记录；赛季内累计到一定次数会触发罚位（F1：第五次训诫若含驾驶类违规，下一站罚退 10 位——以当年规则为准）。':
      'Light: a warning or reprimand on the driver’s record. Enough of them in a season can mean a grid drop (F1: a fifth reprimand that includes a driving offence drops you 10 places at the next round — check that year’s rules).',
  '罚时：5 秒或 10 秒罚时，进站时在维修区停满相应秒数、期间不许碰车；不再进站则赛后加到总成绩上。':
      'Time penalty: 5 or 10 seconds, served stationary in the pit lane with nobody touching the car. If you do not pit again, it is added to the result.',
  '通过维修区（drive-through）：不停车、以维修区限速穿过维修区；须在通知后两圈内执行。':
      'Drive-through: do not stop. Drive the pit lane at the pit speed limit. Serve it within two laps of being told.',
  '10 秒停站（stop-and-go）：在维修区停车 10 秒、期间不许修车；比通过维修区更重。':
      '10-second stop-and-go: stop in the pits for 10 seconds. No work on the car. Heavier than a drive-through.',
  '罚位（grid penalty）：下一场比赛发车位后退若干位；常见原因包括排位赛阻挡、技术违规等（F1 另有动力单元超额罚退）。':
      'Grid penalty: start further back at the next race. Typical causes include blocking in qualifying or a technical breach (F1 also drops places for extra power-unit parts).',
  '取消资格：黑旗（比赛中）或赛后取消成绩；技术违规或极端危险驾驶可直接取消资格。':
      'Disqualification: a black flag during the race, or the result deleted afterward. A technical breach or extremely dangerous driving can exclude you outright.',
  '超级驾照扣分：F1 车手 12 个月内累计 12 分自动停赛一场；2026 年起扣分范围收窄至危险/鲁莽/不体育道德行为（来源：F1 处罚规则解读）。':
      'Super Licence points: 12 points in 12 months means an automatic one-race ban. From 2026 the points apply only to dangerous, reckless, or unsportsmanlike conduct (F1 penalty guide).',
  '一套规则，多项赛事：通用与特有': 'One rulebook, many series: shared and specific',
  '不用每项赛事重学一遍规则——旗语和罚则基本通用，特例只在耐力赛和个别赛制上。':
      'You do not relearn the rules for every series. Flags and penalties are mostly shared. The exceptions are endurance and a few formats.',
  '旗语通用：FIA 附录 H 的旗语适用于 F1、GT3、WEC、CTCC 等全部 FIA 场地赛；FIM 旗语适用于 MotoGP、WSBK、ARRC、CSBK；赛道日沿用同一套。':
      'Shared flags: FIA Appendix H covers F1, GT3, WEC, CTCC, and other FIA circuit races. FIM flags cover MotoGP, WSBK, ARRC, and CSBK. Track days use the same set.',
  '安全车基本通用，勒芒除外：安全车带队、禁超车、差距清零的原则各 FIA 赛事相同；但勒芒没有虚拟安全车，用三辆安全车+慢速区+全场黄旗。':
      'The safety car is mostly shared, except Le Mans: lead car, no passing, gaps wiped, across FIA series. Le Mans has no VSC. It uses three safety cars, slow zones, and a full-course yellow.',
  '罚则工具通用：罚时、通过维修区、10 秒停站、罚位、取消资格是 FIA 各赛事共用的罚则梯度；但“进站只限换胎”是 F1 安全车/虚拟安全车下的特殊规定，耐力赛安全车下仍可加油、换胎、换人。':
      'Shared penalty tools: time, drive-through, 10-second stop-and-go, grid drop, and exclusion are the FIA ladder. “Tires only” under a safety car or VSC is an F1 rule. In endurance you can still refuel, change tires, and change drivers under the safety car.',
  'F1 专属别套用：超级驾照 12 分停赛、训诫累计罚退、动力单元超额罚退，都是 F1 才有的规则，不适用于 GT、WEC 与国内赛事。':
      'Do not copy F1-only rules: the 12-point ban, reprimand grid drops, and extra power-unit drops exist in F1, not in GT, WEC, or domestic series.',
  '积分各不相同：F1 与 WEC 6 小时站冠军同为 25 分，但 WEC 按组别单独排名、按时长分档、勒芒双倍；WSBK 与 MotoGP 积分表相同；CTCC、中国 GT、CEC 的积分以当年规则为准（未核实具体分值）。':
      'Points differ: an F1 win and a WEC 6-hour win are both 25, but WEC scores each class, scales by duration, and doubles Le Mans. WSBK and MotoGP use the same table. CTCC, China GT, and CEC points follow that year’s rules (specific values unverified).',
  'BoP 是 GT 与耐力的专属概念：F1 没有性能平衡（靠规则+成本帽），GT3、LMGT3、Hypercar 靠 BoP 拉平不同厂商；看 GT 与耐力赛要先懂 BoP。':
      'Balance of Performance is a GT and endurance idea. F1 has no BoP (it uses rules and a cost cap). GT3, LMGT3, and Hypercar use BoP to even out makers. You need BoP to follow GT and endurance.',
  '赛事架构': 'How a race is built',
  '比赛周末、组别与积分': 'Weekends, classes, and points',
  '比赛周末：以 F1 与 MotoGP 为例': 'A race weekend: F1 and MotoGP',
  '一个周末三天，练习是学习、排位是考试、正赛是结果。':
      'Three days. Practice is learning, qualifying is the test, the race is the result.',
  'F1 标准周末：周五两节练习（FP1、FP2，各 60 分钟），周六一节练习（FP3）+ 排位赛，周日正赛；排位分 Q1/Q2/Q3 淘汰制，Q3 最快者获杆位。':
      'A standard F1 weekend: Friday FP1 and FP2 (60 minutes each), Saturday FP3 plus qualifying, Sunday the race. Qualifying is Q1/Q2/Q3 knockout. The fastest in Q3 takes pole.',
  'MotoGP 周末：周五 FP1（45 分钟）+ 计时练习（60 分钟，决定 Q2 直通名额），周六 FP2、Q1/Q2 排位与冲刺赛，周日暖胎圈后正赛。':
      'A MotoGP weekend: Friday FP1 (45 minutes) plus timed practice (60 minutes, which decides who goes straight to Q2), Saturday FP2, Q1/Q2, and the sprint, Sunday a warm-up lap then the race.',
  '练习赛不计积分，只用于调车与熟悉赛道；排位赛决定发车顺序。':
      'Practice scores no points. It is for setup and learning the track. Qualifying sets the grid.',
  '冲刺赛周末：F1 全年仅 6 站、MotoGP 每站都有，周五只剩一节练习（F1）或排位结构调整（MotoGP 2027 年起冲刺赛单独排位）。':
      'Sprint weekends: F1 has only 6 a year; MotoGP has one every round. Friday is then a single practice (F1), or the qualifying shape changes (from 2027 MotoGP gives the sprint its own qualifying).',
  '冲刺赛与耐力赛': 'Sprints and endurance',
  '短跑拼爆发，长跑拼耐力与团队。':
      'A sprint is a burst. Endurance is stamina and a team.',
  '冲刺赛：距离约为正赛一半（F1 约 100 公里、无强制进站；MotoGP 约 20 分钟），积分较少但同样计入年度积分。':
      'Sprint: about half a race (F1 about 100 km, no mandatory stop; MotoGP about 20 minutes). Fewer points, still counted for the year.',
  '耐力赛（如勒芒 24 小时、WEC）：多名车手轮流驾驶同一辆车、持续数小时至 24 小时；进站加油换胎换人是比赛的一部分，策略与可靠性比单圈速度更重要。':
      'Endurance (Le Mans 24 Hours, WEC): several drivers share one car for hours, up to 24. Fuel, tires, and driver changes are part of the race. Strategy and reliability matter more than one lap.',
  'WSBK 的 Superpole Race：10 圈短途赛，成绩决定周日第二场正赛的发车位。':
      'WSBK Superpole Race: a 10-lap sprint. Its result sets the grid for Sunday’s second race.',
  '赛道日没有冲刺赛与耐力赛的概念，但分组计时赛（time attack）与耐力体验活动借用了类似形式。':
      'Track days have no sprint or endurance. Timed groups (time attack) and endurance experiences borrow the shape.',
  '组别、积分与发车进站': 'Classes, points, starts, and stops',
  '不同组别比的是同场不同规则，积分只奖励前列。':
      'Classes race together under different rules. Points reward only the front.',
  '组别：方程式（单座赛车，如 F1/F2/F3）、GT（基于量产跑车的 GT3/GT4）、量产组/房车（touring car）、原型车（耐力赛 Hypercar/LMP2）；同场多组别时各组分别排名。':
      'Classes: formula (single-seaters such as F1/F2/F3), GT (GT3/GT4 from road cars), touring cars, and prototypes (endurance Hypercar/LMP2). When classes share a race, each is classified on its own.',
  '积分逻辑：只奖励完赛前列，名次越高分越多；F1 正赛前 10 名得分（冠军 25 分），冲刺赛前 8 名（冠军 8 分）；MotoGP 正赛前 15 名（冠军 25 分），冲刺赛前 9 名（冠军 12 分）。单站满分：F1 冲刺周末 33 分，MotoGP 37 分。':
      'Points logic: only the front of the finishers score, and a higher place scores more. F1 race: top 10 (win 25). Sprint: top 8 (win 8). MotoGP race: top 15 (win 25). Sprint: top 9 (win 12). A perfect round is 33 in an F1 sprint weekend and 37 in MotoGP.',
  '发车：排位定顺序，灯灭起跑；抢跑、发车区违规会被罚。':
      'The start: qualifying sets the order, lights out means go. A jump start or a grid infringement is penalized.',
  '进站：换胎停站极短、进站窗口与轮胎策略常决定胜负；进站时维修区限速，超速受罚。（未核实：F1 换胎停站时长约 2 秒量级，以当年实测为准，此处仅作量级参考。）':
      'Pit stops: a tire stop is very short, and the window plus tire strategy often decide the race. The pit lane has a speed limit; speeding is penalized. (Unverified: an F1 tire stop is on the order of 2 seconds. Use that year’s measurement. This is only a scale.)',
  'GT3 是什么': 'What GT3 is',
  'GT3 是全球 GT 赛车最通用的规则，量产跑车改出来的赛车，靠性能平衡让不同品牌同场竞技。':
      'GT3 is the most widely used GT rule set: race cars built from road cars, evened out by Balance of Performance so different brands can race together.',
  '量产跑车改装：GT3 赛车以量产高性能跑车为基础改装（保时捷 911、法拉利 296、宝马 M4 等），厂商每年须先量产至少 300 台公路车才能申请 FIA GT3 认证，规则由 SRO 管理。':
      'Based on a road car: a GT3 car is a modified production sports car (Porsche 911, Ferrari 296, BMW M4, and others). A maker must build at least 300 road cars a year before applying for FIA GT3 homologation. SRO runs the rules.',
  '性能数据：马力约 500–600 匹、车重约 1200–1300 公斤（受 BoP 调整影响，数值会变）。':
      'Performance: about 500–600 hp and about 1200–1300 kg. BoP changes those numbers.',
  'BoP 性能平衡：不同品牌发动机布局、重量、气动天然不同，组委会通过加配重、限制进气/增压值、调整离地间隙和油箱容量，把各车圈速拉到接近；按实测数据逐站调整，没有 BoP 就一家独大。':
      'Balance of Performance: engines, weight, and aero differ by brand. The organizer adds ballast, limits intake or boost, and changes ride height and fuel capacity so lap times stay close. It is adjusted from measured data, round by round. Without BoP one car would dominate.',
  '为什么是它：规则统一、成本可控，全球几十个系列共用同一套 GT3 规则，一台车能在欧洲、亚洲、美洲和勒芒的 GT 组别参赛。':
      'Why it exists: one rule set and a controllable cost. Dozens of series worldwide use GT3, so one car can race in Europe, Asia, the Americas, and the GT class at Le Mans.',
  'GT 世界挑战赛：冲刺与耐力': 'GT World Challenge: sprint and endurance',
  'GT3 的顶级舞台，分冲刺杯和耐力杯两条线，斯帕 24 小时是招牌。':
      'The top GT3 stage, split into a Sprint Cup and an Endurance Cup. The Spa 24 Hours is the signature race.',
  '两条线：GT World Challenge Europe 分冲刺杯与耐力杯，各 5 站，积分合并计年度总冠军；另有亚洲、美洲等区域系列。':
      'Two series: GT World Challenge Europe has a Sprint Cup and an Endurance Cup, five rounds each, with points combined for the year. There are also Asia, America, and other regional series.',
  '冲刺杯：每站两场 1 小时正赛，两名车手共用一台车，每场各有一节排位定发车位，强制进站换人。':
      'Sprint Cup: two one-hour races per round, two drivers in one car, a qualifying session for each race, and a mandatory driver change.',
  '耐力杯：3 小时或 6 小时正赛，三名车手轮换；斯帕 24 小时是赛季重头戏，非 Pro 组可上第四名车手；斯帕在 6 小时、12 小时和完赛时都发积分。':
      'Endurance Cup: 3-hour or 6-hour races with three drivers. The Spa 24 Hours is the centerpiece. Non-Pro entries may add a fourth driver. Spa scores at 6 hours, 12 hours, and the finish.',
  '车手分级：FIA 把车手评为铂金/金/银/铜四档；据此分 Pro（职业车手争总冠军）、金杯、银杯、铜杯（业余车手+职业搭档），同场不同组分别排名。':
      'Driver grades: the FIA rates drivers Platinum, Gold, Silver, or Bronze. That splits Pro (professionals for the overall title), Gold Cup, Silver Cup, and Bronze Cup (amateurs with a pro teammate). They race together and are classified separately.',
  '耐力赛排位：三名车手各跑一节排位，综合成绩定发车位（与 F1 单人排位不同）。':
      'Endurance qualifying: each of the three drivers runs a session. The combined time sets the grid (unlike F1’s single-driver qualifying).',
  'WEC 世界耐力锦标赛': 'WEC, the World Endurance Championship',
  '耐力赛的世界杯，分站从 6 小时到 24 小时，两个组别同场、按组别分别排名。':
      'The world cup of endurance. Rounds run from 6 hours to 24. Two classes share the track and are classified separately.',
  '两个组别：Hypercar（顶级原型车，厂商队）与 LMGT3（GT3 规则的量产跑车组，2024 年起取代 LMGTE）；勒芒时另加 LMP2 组；全年约 8 站。':
      'Two classes: Hypercar (top prototypes, factory teams) and LMGT3 (production-based GT3, replacing LMGTE from 2024). Le Mans also adds LMP2. About eight rounds a year.',
  '比赛时长：多数分站 6 小时，另有 8 小时（巴林）与约 10 小时的卡塔尔 1812 公里站，勒芒 24 小时是压轴。':
      'Duration: most rounds are 6 hours, plus 8 hours at Bahrain and the roughly 10-hour Qatar 1812 km. Le Mans, at 24 hours, closes the year.',
  '排位与 Hyperpole：每组别先跑 12 分钟排位，前 10 名进入 10 分钟 Hyperpole 争杆位；杆位车组加 1 分；勒芒用两阶段 Hyperpole（先 15 进 10，再 10 争杆）。':
      'Qualifying and Hyperpole: each class runs 12 minutes. The top 10 go to a 10-minute Hyperpole for pole. Pole is worth 1 point. Le Mans uses two Hyperpole stages (15 down to 10, then 10 for pole).',
  '积分按时长分档：6 小时站冠军 25 分（与 F1 相同：25-18-15-12-10-8-6-4-2-1，前 10 名）；8–10 小时站冠军 38 分；勒芒冠军 50 分；各组别单独计分。':
      'Points scale with duration: a 6-hour win is 25 (the F1 scale, 25-18-15-12-10-8-6-4-2-1, top 10). An 8–10 hour win is 38. Le Mans is 50. Each class scores on its own.',
  'BoP 也在这里：Hypercar 与 LMGT3 同样用性能平衡调校不同厂商的车，近年 BoP 具体数值不再对外公开。':
      'BoP is here too: Hypercar and LMGT3 are balanced across makers. In recent years the exact BoP figures are not published.',
  '勒芒 24 小时：为什么特殊': 'The Le Mans 24 Hours: why it is different',
  '耐力赛的皇冠，一天一夜比谁跑得最远，规则处处与普通分站不同。':
      'The crown of endurance. A day and a night of who goes furthest. The rules differ from a normal round in many places.',
  '比距离不比圈数：24 小时内谁跑的总里程最长谁赢；萨尔特赛道 13.626 公里，约 70% 全油门、极速约 350 公里/时。':
      'Distance, not laps: whoever covers the most ground in 24 hours wins. The Circuit de la Sarthe is 13.626 km, about 70% full throttle, with a top speed around 350 km/h.',
  '三辆安全车：赛道太长（13.6 公里），三辆安全车分别停在维修区出口、Arnage 弯和第一个穆桑直道减速弯，出事就近出动；没有虚拟安全车（VSC）。':
      'Three safety cars: the track is long (13.6 km). One waits at pit exit, one at Arnage, one at the first Mulsanne chicane, and the nearest one goes. There is no VSC.',
  '慢速区（Slow Zone）：局部出事时只封锁该路段，限速 80 公里/时、禁超车，其余路段继续比赛；配合全场黄旗（FCY，同样 80 公里/时）使用。':
      'Slow Zone: a local incident closes only that stretch, at 80 km/h with no passing. The rest of the track keeps racing. A full-course yellow (FCY) is also 80 km/h.',
  '车手时间上限：每名车手 6 小时内最多开 4 小时、全场最多 14 小时；LMP2 与 LMGT3 组的铜牌、银牌车手全场至少各开 6 小时；高温（≥32°C）时单节连续驾驶限 80 分钟、两节之间至少休息 30 分钟。':
      'Driving-time limits: no driver may do more than 4 hours in any 6, or more than 14 in the race. In LMP2 and LMGT3, Bronze and Silver drivers must each do at least 6 hours. In heat (≥32°C) a stint is limited to 80 minutes, with at least 30 minutes of rest between stints.',
  '积分双倍：勒芒冠军 50 分，是普通 6 小时站的两倍，年度争冠的关键一战。':
      'Double points: a Le Mans win is 50, twice a normal 6-hour round, so it decides the championship.',
  '参赛规模：62 台车同场，Hypercar、LMP2、LMGT3 三组混跑，慢车与快车同场是常态。':
      'The field: 62 cars, Hypercar, LMP2, and LMGT3 together. Slow and fast cars sharing the track is normal.',
  '中国汽车赛事：CTCC、中国 GT、CEC': 'Chinese car racing: CTCC, China GT, CEC',
  '国内三大场地赛：房车、GT 冲刺、耐力，各有一套玩法。':
      'Three domestic circuit series: touring cars, GT sprints, and endurance. Each has its own format.',
  'CTCC 中国汽车场地职业联赛：国内房车顶级赛，创办于 2004 年；现分超级组（TCR 赛车）与运动杯（量产车）；周末一般两节 30 分钟练习、两节排位（Q1/Q2）、两场约 30 分钟正赛。':
      'CTCC: China’s top touring-car series, founded in 2004. It now has a Super class (TCR cars) and a Sports Cup (production cars). A weekend is usually two 30-minute practices, two qualifying sessions (Q1/Q2), and two races of about 30 minutes.',
  '中国 GT 锦标赛：国内 GT 冲刺赛，分 GT3、GTC、GTS 组；每站每组两场正赛（约 55 分钟+1 圈），强制进站换人；按 Pro/Pro-Am/Am/大师组分级。':
      'China GT Championship: the domestic GT sprint series, in GT3, GTC, and GTS. Each class runs two races a round (about 55 minutes plus a lap) with a mandatory driver change. Grades are Pro, Pro-Am, Am, and Masters.',
  'CEC 中国汽车耐力锦标赛：国内唯一的场地耐力锦标赛；全年 5 站，4 小时、6 小时、12 小时耐力赛；分 GT 杯（原型车、GT3、GT4、GTC、TCE）与国家杯（GTL、TCE、2000/2000T、1600/1600T）两大系列，多车手轮换、滚动发车。':
      'CEC: China’s only circuit endurance championship. Five rounds, at 4, 6, and 12 hours. The GT Cup covers prototypes, GT3, GT4, GTC, and TCE. The National Cup covers GTL, TCE, 2000/2000T, and 1600/1600T. Several drivers share a car, and the start is a rolling start.',
  '共同点：三项都是体育总局批准的国家级 A 类赛事；旗语、安全车、处罚沿用 FIA 体系（见规则分类），不用另学一套。':
      'What they share: all three are national Class A events approved by the sports administration. Flags, the safety car, and penalties follow the FIA system (see the rules section). You do not learn a second set.',
  '澳门格兰披治大赛车': 'The Macau Grand Prix',
  '一年一度、街道封路的赛车嘉年华，汽车与摩托同场，容错率全世界最低。':
      'A once-a-year street race. Cars and bikes share the week. There is almost no room for a mistake.',
  '东望洋跑道：6.120 公里临时街道赛，24 个弯；滨海直道极速约 260 公里/时，山区路段窄到发夹弯仅 7 米宽，全程护墙、没有缓冲区。':
      'The Guia circuit: 6.120 km of temporary street track, 24 corners. The waterfront straight is about 260 km/h. The mountain section narrows to a 7-metre hairpin. Walls the whole way, no runoff.',
  '一周七赛：每年 11 月举行；头条是 FIA FR 世界杯（2024 年起用 Formula Regional 赛车，此前为 F3），另有 FIA GT 世界杯（GT3 赛车，2015 年加入）、东望洋大赛（TCR 世界巡回赛）、澳门摩托车大奖赛等。':
      'Seven races in a week, every November. The headline is the FIA FR World Cup (Formula Regional cars from 2024; it was F3 before), plus the FIA GT World Cup (GT3, added in 2015), the Guia Race (TCR World Tour), the Macau Motorcycle Grand Prix, and others.',
  'GT 世界杯：单场决胜的 GT3 邀请赛，18 台车、8 个厂商同场（2026 年）；周日正赛 16 圈。':
      'GT World Cup: a one-race GT3 invitation. 18 cars and 8 makers (2026). Sunday’s race is 16 laps.',
  '摩托车大奖赛：1967 年起举办，公认最难的摩托街道赛之一，与曼岛 TT 常被相提并论；2026 年为第 58 届，正赛 12 圈。':
      'Motorcycle Grand Prix: held since 1967, one of the hardest bike street races, often named next to the Isle of Man TT. 2026 is the 58th edition. The race is 12 laps.',
  '街道赛的特殊性：赛道就是日常公路，比赛周才封路；没有试车日，车手靠走路、看录像记赛道；撞墙即退赛，安全车与红旗比普通赛道更常见。':
      'Why a street race is different: the track is a public road, closed only for race week. There is no test day. Drivers learn it by walking and watching video. Hitting the wall ends your race. Safety cars and red flags are more common than on a permanent circuit.',
  'WSBK 世界超级摩托车锦标赛': 'WSBK, the World Superbike Championship',
  '量产超跑的世界杯，与 MotoGP 原型车相对：车是能买到的，比赛更贴身。':
      'The world cup for production superbikes, opposite MotoGP’s prototypes: the bikes can be bought, and the racing is closer.',
  '量产车对原型车：WSBK 赛车以市售量产超跑改装（杜卡迪 Panigale V4 R、雅马哈 R1 等），四缸 1000cc、双缸最高 1200cc；MotoGP 是从零造的原型车，两者技术自由度完全不同。':
      'Production vs prototype: a WSBK bike is a modified road superbike (Ducati Panigale V4 R, Yamaha R1, and others), 1000 cc for fours and up to 1200 cc for twins. A MotoGP bike is a prototype built from scratch. The technical freedom is completely different.',
  '周末三场正赛：周五练习、周六单节 15 分钟 Superpole 排位（须跑进杆位车手 105% 以内才有资格）+ Race 1；周日上午 10 圈 Superpole Race，下午 Race 2；全年 12 站（2026 年）。':
      'Three races a weekend: Friday practice, Saturday one 15-minute Superpole (you must be within 105% of pole to qualify) plus Race 1; Sunday morning a 10-lap Superpole Race, afternoon Race 2. Twelve rounds in 2026.',
  'Superpole Race 定发车：Superpole Race 前 9 名按名次排 Race 2 前三排，第 10 名起按排位赛成绩排。':
      'The Superpole Race sets the grid: its top 9 fill the first three rows of Race 2. From 10th back, qualifying order is used.',
  '积分：两场全长正赛前 15 名得分（冠军 25 分，与 MotoGP 相同：25-20-16-13-11-10-9-8-7-6-5-4-3-2-1）；Superpole Race 前 9 名得分（冠军 12 分：12-9-7-6-5-4-3-2-1，与 MotoGP 冲刺赛相同）。':
      'Points: the two full races score the top 15 (a win is 25, the MotoGP scale: 25-20-16-13-11-10-9-8-7-6-5-4-3-2-1). The Superpole Race scores the top 9 (a win is 12: 12-9-7-6-5-4-3-2-1, the same as a MotoGP sprint).',
  '组别：主赛 WorldSBK 之外有 WorldSSP（600cc 级中量级，Next Generation 规则平衡不同排量与缸数）与 WorldSPB（2026 年起取代 WorldSSP300 的轻量级）。':
      'Classes: beside WorldSBK there is WorldSSP (the 600 cc middle class, with Next Generation rules balancing capacity and cylinder count) and WorldSPB (the lightweight class that replaces WorldSSP300 from 2026).',
  '亚洲与中国摩托赛事：ARRC、CSBK': 'Asian and Chinese bike racing: ARRC, CSBK',
  '亚洲与国内的摩托顶级赛，是车手通往世界舞台的台阶。':
      'The top bike series in Asia and at home. They are the step toward the world stage.',
  'ARRC 亚洲公路摩托车锦标赛：FIM 认证、1996 年创办的亚洲顶级量产摩托赛，全年 6 站；分 ASB1000（1000cc 超级摩托）、SS600（600cc）、AP250（250cc 量产）、UB150（150cc 弯梁车）四组，每站每组两场正赛。':
      'ARRC, the Asia Road Racing Championship: FIM-sanctioned, founded in 1996, Asia’s top production-bike series, six rounds. Four classes: ASB1000 (1000 cc superbike), SS600 (600 cc), AP250 (250 cc production), and UB150 (150 cc underbone). Two races per class per round.',
  '定位：亚洲车手的晋升通道，表现好的车手由此走向 MotoGP/WSBK 体系；统一轮胎为邓禄普（合约至 2031 年）。':
      'Role: the ladder for Asian riders toward MotoGP or WSBK. The control tire is Dunlop (contract through 2031).',
  'CSBK 中国超级摩托车锦标赛：体育总局批准的国家级 A 类赛事，2007 年设立，是国内排量最大、速度最快的摩托赛；与全国公路摩托车锦标赛（CRRC）实行组别晋级，CRRC 优秀车手升入 CSBK。':
      'CSBK, the China Superbike Championship: a national Class A event approved by the sports administration, set up in 2007, the largest-capacity and fastest bike series in the country. It promotes with the national road-race championship (CRRC): strong CRRC riders move up to CSBK.',
  '组别沿革（未核实最新）：2017 年分 SSP 超级量产组、SSO 超级运动组、SBK 超级公开组三组；2018 年增至 7 组（含 250cc 公开组、Honda 190 统一组、新秀组、青少组）；近年组别有调整，最新以当年秩序册为准。':
      'Class history (latest year unverified): in 2017 there were SSP, SSO, and SBK. In 2018 that grew to 7 classes (including a 250 cc open class, a Honda 190 one-make class, a rookie class, and a youth class). Classes have changed since. Use that year’s regulations.',
  '赛制：CSBK 每站一般两回合较量，按全年个人与车队积分定总名次（2017 年赛制，最新以当年为准）。':
      'Format: CSBK usually runs two races a round, with the year decided on rider and team points (the 2017 format; use that year’s rules).',
  '赛道日准备': 'Getting ready for a track day',
  '车、证件与随身物品': 'The car, the papers, and what you carry',
  '车辆准备清单': 'Vehicle checklist',
  '车况是入场券，赛前按表检查一遍。':
      'The condition of the vehicle is the ticket in. Check the list before you go.',
  '汽车：轮胎（花纹、胎压、螺栓扭矩）、刹车（刹车片余量、刹车油、刹车盘）、机油/冷却液/无泄漏、电瓶固定、车内清空、头盔。':
      'Car: tires (tread, pressure, bolt torque), brakes (pad thickness, fluid, discs), oil and coolant with no leaks, a secured battery, an empty cabin, and a helmet.',
  '摩托：轮胎、刹车、链条张力与润滑、机油/冷却液无泄漏、灯光与后视镜贴掉或拆除、拉杆护弓、噪音达标。':
      'Bike: tires, brakes, chain tension and lube, no oil or coolant leaks, lights and mirrors taped or removed, a lever guard, and a legal noise level.',
  '建议：提前一周做一次常规保养；赛前一天按主办方车检表逐项自查并签字；带上胎压表与扭矩扳手。':
      'Suggestion: do a normal service a week ahead. The day before, walk the organizer’s scrutineering sheet and sign it. Bring a pressure gauge and a torque wrench.',
  '油：出发前加满油；赛道内不一定有加油站，提前算好油耗、多带备用油更稳妥。':
      'Fuel: fill up before you leave. The circuit may have no pump. Estimate consumption and bring spare fuel.',
  '证件、装备与随身物品': 'Papers, gear, and what to carry',
  '忘带证件等于白跑一趟。': 'Forget the papers and the trip was for nothing.',
  '证件：驾驶证、报名确认单、已签署的免责书、车检表。':
      'Papers: driving licence, entry confirmation, a signed waiver, and the scrutineering form.',
  '汽车装备：头盔（按主办方标准，常见 Snell SA2020）、长袖长裤（天然纤维为佳）、封闭鞋、水。':
      'Car gear: a helmet to the organizer’s standard (often Snell SA2020), long sleeves and trousers (natural fibre is preferred), closed shoes, and water.',
  '摩托装备：全盔、连体皮衣或 360° 拉链分体皮衣、手套、靴子、护背。':
      'Bike gear: a full-face helmet, a one-piece suit or a two-piece with a 360° zipper, gloves, boots, and a back protector.',
  '随身：水（比想象中更需要）、防晒、折叠椅、工具（胎压表、内六角、扎带、胶带）、备用油、充电宝。':
      'Carry: more water than you think, sunscreen, a folding chair, tools (pressure gauge, hex keys, zip ties, tape), spare fuel, and a power bank.',
  '到场流程：签到 → 噪音/车检 → 安全简报（强制）→ 熟悉圈 → 分组上场。':
      'On arrival: sign in, noise and scrutineering, the mandatory briefing, a sighting lap, then your group.',
  '术语': 'Terms',
  '看懂成绩单与赛道黑话': 'Reading a timing sheet and the track’s words',
  '圈与计时术语': 'Lap and timing words',
  '看懂这几个词，才看得懂成绩单。':
      'Learn these words and a timing sheet makes sense.',
  '出场圈（out lap）：从维修区出来、进入计时圈之前的一圈，用于暖胎暖刹。':
      'Out lap: the lap from the pits before a timed lap. It warms the tires and brakes.',
  '飞驰圈（flying lap）：全速计时的一圈；成绩单上的单圈时间一般指飞驰圈。':
      'Flying lap: a timed lap at full pace. A lap time on a sheet is usually a flying lap.',
  '冷却圈/回场圈（in lap / cool-down lap）：冲线后减速回维修区的一圈，顺带给刹车与轮胎降温。':
      'In lap / cool-down lap: the lap after the flag, slowing back to the pits and cooling the brakes and tires.',
  '分段（sector）：赛道被分成 2–3 个计时段，分段成绩用于分析哪里快、哪里慢。':
      'Sector: the track split into 2 or 3 timed parts. Sector times show where you were fast or slow.',
  'Delta：与参考圈（通常是个人最快圈）的实时时间差；负值表示比参考圈快。':
      'Delta: the live time gap to a reference lap, usually your best. Negative means you are ahead of that lap.',
  '弯心（apex）：走线最贴近弯内侧的点；刹车区（braking zone）：刹车开始到入弯的路段。':
      'Apex: the point where the line is closest to the inside. Braking zone: from where you start braking to turn-in.',
  '赛道与车辆术语': 'Track and car words',
  '赛道边的黑话，听到就懂。': 'The words you hear at the fence.',
  '维修区（pit lane）：与主赛道平行的通道，限速行驶；维修站（pit box）：车队换胎修车的位置。':
      'Pit lane: the lane beside the track, driven at a speed limit. Pit box: where the team changes tires and works on the car.',
  '封闭管理区（parc fermé）：赛后车辆集中停放检查的区域，车队不得随意改动车辆（正赛规则，赛道日一般无此环节）。':
      'Parc fermé: where cars are parked for checks after a session. The team may not change the car freely. That is a race rule. Track days usually skip it.',
  '赛道限制（track limits）：赛车须保持在赛道白线以内，四轮出白线即为超出限制，排位圈会被删除、正赛会受罚。':
      'Track limits: the car must stay inside the white lines. Four wheels beyond the line is a breach. A qualifying lap can be deleted, and a race lap can be penalized.',
  '路肩（kerb）：弯内外侧的红白（或其他颜色）凸起路缘，可压但别依赖。':
      'Kerb: the raised red-and-white (or other colour) edge inside or outside a corner. You can use it. Do not rely on it.',
  '缓冲区（run-off）：弯外的铺装或砂石区域，供失控车辆减速；砂石区（gravel trap）减速效果强但容易陷车。':
      'Run-off: the paved or gravel area outside a corner, for a car that has lost it. A gravel trap slows you hard but can bog the car.',
  '暖胎圈（formation lap / warm-up lap）：正赛发车前绕场一圈暖胎；摩托亦有暖胎圈（warm-up lap）。':
      'Formation lap / warm-up lap: the lap before a race start, to warm the tires. Bikes have a warm-up lap too.',
  'FIA 旗语与规则（Aston Martin F1 规则解读）':
      'FIA flags and rules (Aston Martin F1 rules guide)',
  'MotoGP 旗语（FIM 大奖赛规则）': 'MotoGP flags (FIM Grand Prix rules)',
  'F1 安全车与虚拟安全车规则': 'F1 safety car and virtual safety car rules',
  'F1 处罚规则': 'F1 penalty rules',
  'MotoGP 冲刺赛': 'MotoGP sprint',
  'MSV 赛道日规则与新手指南': 'MSV track-day rules and novice guide',
  'BoP 性能平衡机制（Racer）': 'Balance of Performance (Racer)',
  'GT World Challenge Europe 赛制与分级（Pit Debrief）':
      'GT World Challenge Europe format and grades (Pit Debrief)',
  'WEC 规则、组别与积分（WEC Dashboard）':
      'WEC rules, classes, and points (WEC Dashboard)',
  '勒芒特别规则：安全车/慢速区/车手时间（Daily Sportscar）':
      'Le Mans specifics: safety cars, slow zones, driving time (Daily Sportscar)',
  'WSBK 官方术语表（worldsbk.com）': 'WSBK official glossary (worldsbk.com)',
  'CTCC 组别与历史（Wikipedia）': 'CTCC classes and history (Wikipedia)',
  'CEC 2026 参赛手册（51GT3）': 'CEC 2026 entry handbook (51GT3)',
  '澳门东望洋跑道与大赛车（SnapLap）': 'Macau Guia circuit and Grand Prix (SnapLap)',
};

/// English text for a knowledge string. Chinese is returned when that
/// is the active language, or when no English line exists.
String knowledgeText(bool zh, String source) {
  if (zh) return source;
  return knowledgeEn[source] ?? source;
}
