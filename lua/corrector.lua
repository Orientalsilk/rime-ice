--[[
	错音错字提示（合并版：外部词典 + 内置兜底 + 拼音相似度提示 + 双调式 comment 兼容）

	示例：「给予」的正确读音是 ji yu，当用户输入 gei yu 时，在候选项的 comment 显示正确读音
	示例：「按耐」的正确写法是「按捺」，当用户输入「按耐」时，在候选项的 comment 显示正确写法

	comment 来源兼容两种情况，自动适配，无需手动切换：
	  1) Rime 原生 translator/spelling_hints 生成的 ［quán pīn］ 全角方括号包裹的拼音
	  2) 万象拼音等方案自己的 modify_preedit_filter / super_preedit 直接写入的带调拼音（不带方括号）
	原理：统一先去声调再比对，未带声调的字符串去声调是空操作，所以两种来源都能命中同一张表。

	数据来源（优先级）：
	  1. 外部词典 cn_dicts/cuoyin.dict.yaml（推荐，方便维护）
	     格式：正确词<TAB>错误读音(无调)<TAB>权重<TAB>正确读音(带调)
	  2. 本文件内置 M.builtin_corrections 作为兜底

	拼音相似度提示：精确匹配未命中时，在"同一目标候选文字"对应的已知错误读音里，
	用编辑距离找最接近的一条，容忍用户在已知错误读音基础上又多打错一两个字母。
	可通过 corrector/fuzzy_hint（开关，默认 true）和 corrector/fuzzy_threshold
	（容忍的编辑距离，默认 1）两个配置项调整。

	未命中时的行为：默认完全不碰 comment（兼容场景 2，避免破坏其他 Lua 写入的带调显示）。
	如果你明确只用场景 1、且希望未命中时清空多余的 spelling_hints 提示，
	可以设置 corrector/clear_on_miss: true 开启旧的清空行为。

	配置示例（schema / custom）：
	  corrector:
	    style: "{comment}"
	    fuzzy_hint: true
	    fuzzy_threshold: 1
	    clear_on_miss: false
	    dict: cn_dicts/cuoyin.dict.yaml

	感谢大佬 @Shewer Lu 提供的 spelling_hints 兼容思路。
	外部词典加载思路参考 @amzxyz 万象 super_comment。
--]]

local M = {}

-- ============================================================
-- 内置兜底表（外部词典加载失败时使用；也可与外部词典合并）
-- 完整数据已导出到 cn_dicts/cuoyin.dict.yaml，建议以外部词典为主
-- ============================================================
M.builtin_corrections = {
    -- 错音
    ["hun dun"] = { text = "馄饨", comment = "hún tun" },
    ["zhu jiao"] = { text = "主角", comment = "zhǔ jué" },
    ["jiao se"] = { text = "角色", comment = "jué sè" },
    ["chi pi sa"] = { text = "吃比萨", comment = "chī bǐ sà" },
    ["pi sa bing"] = { text = "比萨饼", comment = "bǐ sà bǐng" },
    ["shui fu"] = { text = "说服", comment = "shuō fú" },
    ["dao hang"] = { text = "道行", comment = "dào heng" },
    ["mo yang"] = { text = "模样", comment = "mú yàng" },
    ["you mo you yang"] = { text = "有模有样", comment = "yǒu mú yǒu yàng" },
    ["yi mo yi yang"] = { text = "一模一样", comment = "yī mú yī yàng" },
    ["zhuang mo zuo yang"] = { text = "装模作样", comment = "zhuāng mú zuò yàng" },
    ["ren mo gou yang"] = { text = "人模狗样", comment = "rén mú gǒu yàng" },
    ["mo ban"] = { text = "模板", comment = "mú bǎn" },
    ["a mi tuo fo"] = { text = "阿弥陀佛", comment = "ē mí tuó fó" },
    ["na mo a mi tuo fo"] = { text = "南无阿弥陀佛", comment = "nā mó ē mí tuó fó" },
    ["nan wu a mi tuo fo"] = { text = "南无阿弥陀佛", comment = "nā mó ē mí tuó fó" },
    ["nan wu e mi tuo fo"] = { text = "南无阿弥陀佛", comment = "nā mó ē mí tuó fó" },
    ["sha di li"] = { text = "刹帝利", comment = "chà dì lì" },
    ["gei yu"] = { text = "给予", comment = "jǐ yǔ" },
    ["bin lang"] = { text = "槟榔", comment = "bīng láng" },
    ["zhang bai zhi"] = { text = "张柏芝", comment = "zhāng bó zhī" },
    ["teng man"] = { text = "藤蔓", comment = "téng wàn" },
    ["nong tang"] = { text = "弄堂", comment = "lòng táng" },
    ["xin kuan ti pang"] = { text = "心宽体胖", comment = "xīn kuān tǐ pán" },
    ["mai yuan"] = { text = "埋怨", comment = "mán yuàn" },
    ["xu yu wei she"] = { text = "虚与委蛇", comment = "xū yǔ wēi yí" },
    ["mu na"] = { text = "木讷", comment = "mù nè" },
    ["gui lie"] = { text = "龟裂", comment = "jūn liè" },
    ["du le le"] = { text = "独乐乐", comment = "dú yuè lè" },
    ["zhong le le"] = { text = "众乐乐", comment = "zhòng yuè lè" },
    ["xun ma"] = { text = "荨麻", comment = "qián má" },
    ["qian ma zhen"] = { text = "荨麻疹", comment = "xún má zhěn" },
    ["mo ju"] = { text = "模具", comment = "mú jù" },
    ["cao zhi"] = { text = "草薙", comment = "cǎo tì" },
    ["cao zhi jing"] = { text = "草薙京", comment = "cǎo tì jīng" },
    ["cao zhi jian"] = { text = "草薙剑", comment = "cǎo tì jiàn" },
    ["jia ping ao"] = { text = "贾平凹", comment = "jiǎ píng wā" },
    ["xue fo lan"] = { text = "雪佛兰", comment = "xuě fú lán" },
    ["qiang jin"] = { text = "强劲", comment = "qiáng jìng" },
    ["tong ti"] = { text = "胴体", comment = "dòng tǐ" },
    ["li neng kang ding"] = { text = "力能扛鼎", comment = "lì néng gāng dǐng" },
    ["ya lv jiang"] = { text = "鸭绿江", comment = "yā lù jiāng" },
    ["da fu bian bian"] = { text = "大腹便便", comment = "dà fù pián pián" },
    ["ka bo zi"] = { text = "卡脖子", comment = "qiǎ bó zi" },
    ["zhi sheng"] = { text = "吱声", comment = "zī shēng" },
    ["chan he"] = { text = "掺和", comment = "chān huo" },
    ["can huo"] = { text = "掺和", comment = "chān huo" },
    ["can he"] = { text = "掺和", comment = "chān huo" },
    ["cheng zhi"] = { text = "称职", comment = "chèn zhí" },
    ["luo shi fen"] = { text = "螺蛳粉", comment = "luó sī fěn" },
    ["tiao huan"] = { text = "调换", comment = "diào huàn" },
    ["tai xing shan"] = { text = "太行山", comment = "tài háng shān" },
    ["jie si di li"] = { text = "歇斯底里", comment = "xiē sī dǐ lǐ" },
    ["fa xiao"] = { text = "发酵", comment = "fā jiào" },
    ["xiao mu jun"] = { text = "酵母菌", comment = "jiào mǔ jūn" },
    ["xiao mu"] = { text = "酵母", comment = "jiào mǔ" },
    ["yin hong"] = { text = "殷红", comment = "yān hóng" },
    ["nuan he"] = { text = "暖和", comment = "nuǎn huo" },
    ["mo ling liang ke"] = { text = "模棱两可", comment = "mó léng liǎng kě" },
    ["pan yang hu"] = { text = "鄱阳湖", comment = "鄱(pó)阳湖" },
    ["bo yang hu"] = { text = "鄱阳湖", comment = "鄱(pó)阳湖" },
    ["bo jing"] = { text = "脖颈", comment = "bó gěng" },
    ["bo jing er"] = { text = "脖颈儿", comment = "bó gěng er" },
    ["niu pi xian"] = { text = "牛皮癣", comment = "niú pí xuǎn" },
    ["hua ban xian"] = { text = "花斑癣", comment = "huā bān xuǎn" },
    ["ti xian"] = { text = "体癣", comment = "tǐ xuǎn" },
    ["gu xian"] = { text = "股癣", comment = "gǔ xuǎn" },
    ["jiao xian"] = { text = "脚癣", comment = "jiǎo xuǎn" },
    ["zu xian"] = { text = "足癣", comment = "zú xuǎn" },
    ["jie zha"] = { text = "结扎", comment = "jié zā" },
    ["hai shen wei"] = { text = "海参崴", comment = "hǎi shēn wǎi" },
    ["hou pu"] = { text = "厚朴", comment = "hòu pò" },
    ["da wan ma"] = { text = "大宛马", comment = "dà yuān mǎ" },
    ["ci ya"] = { text = "龇牙", comment = "zī yá" },
    ["ci zhe ya"] = { text = "龇着牙", comment = "zī zhe yá" },
    ["ci ya lie zui"] = { text = "龇牙咧嘴", comment = "zī yá liě zuǐ" },
    ["tou pi xue"] = { text = "头皮屑", comment = "tóu pí xiè" },
    ["liu an shi"] = { text = "六安市", comment = "lù ān shì" },
    ["liu an xian"] = { text = "六安县", comment = "lù ān xiàn" },
    ["an hui sheng liu an shi"] = { text = "安徽省六安市", comment = "ān huī shěng lù ān shì" },
    ["an hui liu an"] = { text = "安徽六安", comment = "ān huī lù ān" },
    ["an hui liu an shi"] = { text = "安徽六安市", comment = "ān huī lù ān shì" },
    ["nan jing liu he"] = { text = "南京六合", comment = "nán jīng lù hé" },
    ["nan jing shi liu he"] = { text = "南京六合区", comment = "nán jīng lù hé qū" },
    ["nan jing shi liu he qu"] = { text = "南京市六合区", comment = "nán jīng shì lù hé qū" },
    ["nuo da"] = { text = "偌大", comment = "偌(ruò)大" },
    ["yin jiu zhi ke"] = { text = "饮鸩止渴", comment = "饮鸩(zhèn)止渴" },
    ["yin jiu jie ke"] = { text = "饮鸩解渴", comment = "饮鸩(zhèn)解渴" },
    ["gong shang jiao zhi yu"] = { text = "宫商角徵羽", comment = "宫商角(jué)徵羽" },
    ["shan qi deng"] = { text = "氙气灯", comment = "氙(xiān)气灯" },
    ["shan qi da deng"] = { text = "氙气大灯", comment = "氙(xiān)气大灯" },
    ["shan qi shou dian tong"] = { text = "氙气手电筒", comment = "氙(xiān)气手电筒" },
    ["yin gai"] = { text = "应该", comment = "应(yīng)该" },
    ["nian tie"] = { text = "粘贴", comment = "粘(zhān)贴" },
    ["nian yi nian"] = { text = "粘一粘", comment = "粘(zhān)" },
	["shen tu"] = { text = "神荼", comment = "神荼(shū)" },
    ["yu lei"] = { text = "郁垒", comment = "郁垒(lǜ)" },
    ["shen tu yu lei"] = { text = "神荼郁垒", comment = "神荼(shū)郁垒(lǜ)" },
    ["yu lei shen tu"] = { text = "郁垒神荼", comment = "郁垒(lǜ)神荼(shū)" },
    ["tu fan"] = { text = "吐蕃", comment = "吐蕃(bō)" },
    ["tu gu hun"] = { text = "吐谷浑", comment = "吐谷(yù)浑" },
    ["gao ju li"] = { text = "高句丽", comment = "高句(gōu)丽" },
    ["jiao dou shi"] = { text = "角斗士", comment = "角(jué)斗士" },
    ["suo sha mi"] = { text = "缩砂密", comment = "缩(sù)砂密" },
    ["po ji pao"] = { text = "迫击炮", comment = "迫(pǎi)击炮" },
    ["feng chan"] = { text = "封禅", comment = "fēng shàn" },
    ["yuan sui"] = { text = "芫荽", comment = "yán suī" },
    ["wen bo"] = { text = "榅桲", comment = "wēn po" },
    ["bi ji"] = { text = "荸荠", comment = "bí qi" },
    ["rou yi"] = { text = "柔荑", comment = "róu tí" },
    ["rou yi hua xu"] = { text = "柔荑花序", comment = "柔荑(tí)花序" },
    ["shou ru rou yi"] = { text = "手如柔荑", comment = "手如柔荑(tí)" },
    ["wen ting jun"] = { text = "温庭筠", comment = "温庭筠(yún)" },
    ["zhu you tang"] = { text = "朱祐樘", comment = "朱祐樘(chēng)" },
    ["guan ka"] = { text = "关卡", comment = "guān qiǎ" },
    ["san wei zhen huo"] = { text = "三昧真火", comment = "三昧(mèi)真火" },
    ["qing ping zhi mo"] = { text = "青𬞟之末", comment = "青𬞟(pín)之末" },
    ["qi yu qing ping zhi mo"] = { text = "起于青𬞟之末", comment = "起于青𬞟(pín)之末" },
    ["feng qi yu qing ping zhi mo"] = { text = "风起于青𬞟之末", comment = "风起于青𬞟(pín)之末" },
    ["you hui juan"] = { text = "优惠券", comment = "优惠券(quàn)" },
    ["gong quan"] = { text = "拱券", comment = "gǒng xuàn" },
    ["pu ru"] = { text = "哺乳", comment = "bǔ rǔ" },
    ["nao zu zhong"] = { text = "脑卒中", comment = "nǎo cù zhòng" },
    ["fa zhi"] = { text = "阈值", comment = "yù zhí" },
    ["xie hu"] = { text = "潟湖", comment = "xì hú" },
    ["guo pu"] = { text = "果脯", comment = "guǒ fǔ" },
    ["rou pu"] = { text = "肉脯", comment = "ròu fǔ" },
    ["huo luo"] = { text = "饸饹", comment = "hé le" },
    ["pu an suan"] = { text = "脯氨酸", comment = "脯(fǔ)氨酸" },
    ["luo an suan"] = { text = "酪氨酸", comment = "酪(lào)氨酸" },
    ["mei shi zi"] = { text = "没食子", comment = "没(mò)食子" },
    ["shang feng die"] = { text = "裳凤蝶", comment = "裳(cháng)凤蝶" },
    ["bai qi tun"] = { text = "白𬶨豚", comment = "bái jì tún" },
    ["nao gu"] = { text = "桡骨", comment = "ráo gǔ" },
    ["bai zhe bu rao"] = { text = "百折不挠", comment = "百折不挠(náo)" },
    ["zhui xin qi xie"] = { text = "椎心泣血", comment = "椎(chuí)心泣血" },
    ["zhui xin qi xue"] = { text = "椎心泣血", comment = "椎(chuí)心泣血" },
    ["xia chi"] = { text = "挟持", comment = "挟(xié)持" },
    ["hao zhou"] = { text = "亳州", comment = "亳(bó)州" },
    ["niu jing"] = { text = "牛丼", comment = "牛丼(dǎn)" },
    ["niu jing fan"] = { text = "牛丼饭", comment = "牛丼(dǎn)饭" },
    ["an pou"] = { text = "安瓿", comment = "安瓿(bù)" },
    ["an pou ping"] = { text = "安瓿瓶", comment = "安瓿(bù)瓶" },
    ["jie pao"] = { text = "解剖", comment = "jiě pōu" },
    ["pao fen"] = { text = "剖分", comment = "pōu fēn" },
    ["pao fu chan"] = { text = "剖腹产", comment = "剖(pōu)腹产" },
    ["pao gong chan"] = { text = "剖宫产", comment = "剖(pōu)宫产" },
    ["jin kui"] = { text = "金匮", comment = "金匮(guì)" },
    ["qing ping le"] = { text = "清平乐", comment = "清平乐(yuè)" },
    ["ta sha xing"] = { text = "踏莎行", comment = "踏莎(suō)行" },
    ["sha cao"] = { text = "莎草", comment = "suō cǎo" },
    ["shan mu"] = { text = "杉木", comment = "shā mù" },
    ["ju mai cai"] = { text = "苣荬菜", comment = "qǔ mǎi cài" },
    ["li li"] = { text = "李悝", comment = "lǐ kuī" },
    ["gui bu"] = { text = "跬步", comment = "kuǐ bù" },
    ["dao zai shi ni"] = { text = "道在屎溺", comment = "道在屎溺(niào)" },
    ["bao lian tian wu"] = { text = "暴殄天物", comment = "暴殄(tiǎn)天物" },
    ["yi ji du ren"] = { text = "以己度人", comment = "以己度(duó)人" },
    ["yi yu cheng zhen"] = { text = "一语成谶", comment = "一语成谶(chèn)" },
    ["jing gao"] = { text = "甑糕", comment = "甑(zèng)糕" },
    ["zhao xiang"] = { text = "着想", comment = "着(zhuó)想" },
    ["ge zhi wo"] = { text = "胳肢窝", comment = "胳(gā)肢窝" },
    ["yu he"] = { text = "潏河", comment = "潏(jué)河" },
    ["xiao zheng"] = { text = "校正", comment = "校(jiào)正" },
    ["xiao dui"] = { text = "校对", comment = "校(jiào)对" },
    ["jie su"] = { text = "结束", comment = "结束(shù)" },
    ["zi yuan zi ai"] = { text = "自怨自艾", comment = "自怨自艾(yì)" },
    ["gua gua zhui di"] = { text = "呱呱坠地", comment = "呱(gū)呱坠地" },
    ["niu kou"] = { text = "拗口", comment = "拗(ào)口" },
    ["bang bu"] = { text = "蚌埠", comment = "蚌(bèng)埠" },
    ["mi lu"] = { text = "秘鲁", comment = "秘(bì)鲁" },
    ["zhi re"] = { text = "炽热", comment = "炽(chì)热" },
    ["pi yi"] = { text = "裨益", comment = "裨(bì)益" },
    ["gang fu zi yong"] = { text = "刚愎自用", comment = "刚愎(bì)自用" },
    ["ga ran er zhi"] = { text = "戛然而止", comment = "戛(jiá)然而止" },
    ["yi ye bian zhou"] = { text = "一叶扁舟", comment = "一叶扁(piān)舟" },
    ["bo wen qiang shi"] = { text = "博闻强识", comment = "博闻强识(zhì)" },
    ["ben lin"] = { text = "贲临", comment = "贲(bì)临" },
    ["qing zha"] = { text = "倾轧", comment = "倾轧(yà)" },
    ["ren chen"] = { text = "妊娠", comment = "妊娠(shēn)" },
    ["xin xin xue zi"] = { text = "莘莘学子", comment = "莘(shēn)莘学子" },
    ["tuo ben"] = { text = "拓本", comment = "拓(tà)本" },
    ["chui shou ke de"] = { text = "唾手可得", comment = "唾(tuò)手可得" },
    ["xi yun"] = { text = "吸吮", comment = "吸吮(shǔn)" },
    ["xin guang ti pang"] = { text = "心广体胖", comment = "心广体胖(pán)" },
    ["xing su"] = { text = "星宿", comment = "星宿(xiù)" },
    ["ying pin"] = { text = "赝品", comment = "赝(yàn)品" },
    ["yi bao shi han"] = { text = "一曝十寒", comment = "一曝(pù)十寒" },
    ["cu kuang"] = { text = "粗犷", comment = "粗犷(guǎng)" },
    ["xiang dao"] = { text = "巷道", comment = "巷(hàng)道" },
    ["tong xia"] = { text = "恫吓", comment = "dòng hè" },
    ["gui ju"] = { text = "诡谲", comment = "诡谲(jué)" },
    ["you shuo"] = { text = "游说", comment = "游说(shuì)" },
    ["yin li"] = { text = "阴霾", comment = "阴霾(mái)" },
    ["ju tou"] = { text = "噱头", comment = "噱(xué)头" },
    ["shang jia"] = { text = "商贾", comment = "商贾(gǔ)" },
    ["biao han"] = { text = "剽悍", comment = "剽(piāo)悍" },
    ["zong zong"] = { text = "淙淙", comment = "淙(cóng)淙" },
    ["zheng shang"] = { text = "整饬", comment = "整饬(chì)" },
    ["dao shang"] = { text = "捯饬", comment = "捯饬(chì)" },
    ["miao lun"] = { text = "谬论", comment = "谬(miù)论" },
    ["mian mian xiang xu"] = { text = "面面相觑", comment = "面面相觑(qù)" },
    ["ge shou"] = { text = "恪守", comment = "恪(kè)守" },
    ["jiao zhu"] = { text = "角逐", comment = "角(jué)逐" },
    ["ga li"] = { text = "蛤蜊", comment = "蛤(gé)蜊" },
    ["e fu"] = { text = "饿殍", comment = "饿殍(piǎo)" },
    ["ti an"] = { text = "堤岸", comment = "堤(dī)岸" },
    ["cu zao"] = { text = "粗糙", comment = "粗糙(cāo)" },
    ["si ye"] = { text = "肄业", comment = "肄(yì)业" },
    ["tang mu jie she"] = { text = "瞠目结舌", comment = "瞠(chēng)目结舌" },
    ["xian mei"] = { text = "谄媚", comment = "谄(chǎn)媚" },
    ["bu di"] = { text = "不啻", comment = "不啻(chì)" },
    ["bian da"] = { text = "鞭挞", comment = "鞭挞(tà)" },
    ["bian tai"] = { text = "鞭笞", comment = "鞭笞(chī)" },
    ["fu gu zhi qu"] = { text = "附骨之疽", comment = "附骨之疽(jū)" },
	["shou ru rou yi"] = { text = "手如柔荑", comment = "手如柔荑(tí)" },
    -- 错字
    ["pu jie"] = { text = "扑街", comment = "仆街" },
    ["pu gai"] = { text = "扑街", comment = "仆街" },
    ["pu jie zai"] = { text = "扑街仔", comment = "仆街仔" },
    ["pu gai zai"] = { text = "扑街仔", comment = "仆街仔" },
    ["ceng jin"] = { text = "曾今", comment = "曾经" },
    ["an nai"] = { text = "按耐", comment = "按捺(nà)" },
    ["an nai bu zhu"] = { text = "按耐不住", comment = "按捺(nà)不住" },
    ["bie jie"] = { text = "别介", comment = "别价(jie)" },
    ["beng jie"] = { text = "甭介", comment = "甭价(jie)" },
    ["xue mai pen zhang"] = { text = "血脉喷张", comment = "血脉贲(bēn)张 | 血脉偾(fèn)张" },
    ["qi ke fu"] = { text = "契科夫", comment = "契诃(hē)夫" },
    ["zhao cha"] = { text = "找茬", comment = "找碴" },
    ["zhao cha er"] = { text = "找茬儿", comment = "找碴儿" },
    ["cou huo"] = { text = "凑活", comment = "凑合(he)" },
    ["ju hui"] = { text = "钜惠", comment = "巨惠" },
    ["mo xie zuo"] = { text = "魔蝎座", comment = "摩羯(jié)座" },
    ["pi sa"] = { text = "披萨", comment = "比(bǐ)萨" },
    ["geng quan"] = { text = "梗犬", comment = "㹴犬" },
}

-- 运行时表（由 init 填充：内置 + 外部词典）
M.corrections = {}
M.by_text = {}

-- 经典 Levenshtein 编辑距离
local function edit_distance(a, b)
    local la, lb = #a, #b
    if la == 0 then return lb end
    if lb == 0 then return la end

    local prev = {}
    for j = 0, lb do prev[j] = j end

    local cur = {}
    for i = 1, la do
        cur[0] = i
        local ai = a:sub(i, i)
        for j = 1, lb do
            local cost = (ai == b:sub(j, j)) and 0 or 1
            cur[j] = math.min(
                prev[j] + 1,
                cur[j - 1] + 1,
                prev[j - 1] + cost
            )
        end
        prev, cur = cur, prev
    end
    return prev[lb]
end

local tone_map = {
    ["ā"] = "a", ["á"] = "a", ["ǎ"] = "a", ["à"] = "a",
    ["ē"] = "e", ["é"] = "e", ["ě"] = "e", ["è"] = "e",
    ["ī"] = "i", ["í"] = "i", ["ǐ"] = "i", ["ì"] = "i",
    ["ō"] = "o", ["ó"] = "o", ["ǒ"] = "o", ["ò"] = "o",
    ["ū"] = "u", ["ú"] = "u", ["ǔ"] = "u", ["ù"] = "u",
    ["ǖ"] = "v", ["ǘ"] = "v", ["ǚ"] = "v", ["ǜ"] = "v", ["ü"] = "v",
    ["ń"] = "n", ["ň"] = "n", ["ǹ"] = "n",
    ["ḿ"] = "m",
}

local function detone(s)
    if not s then return "" end
    -- 纯 ASCII（无声调）直接跳过；带声调时用表替换，避免对每个字符调用一次 Lua 函数
    if s:find("[\128-\255]") then
        s = s:gsub("[\194-\253][\128-\191]*", tone_map)
    end
    return (s:gsub("%s+", " "):match("^%s*(.-)%s*$") or "")
end

-- 把一条纠错写入运行时表，并维护 by_text 反查
local function add_correction(code, text, comment)
    if not code or not text or not comment then return end
    code = code:match("^%s*(.-)%s*$") or code
    code = code:gsub("%s+", " ")
    text = text:match("^%s*(.-)%s*$") or text
    comment = comment:match("^%s*(.-)%s*$") or comment

    M.corrections[code] = { text = text, comment = comment }

    local list = M.by_text[text]
    if not list then
        list = {}
        M.by_text[text] = list
    end
    table.insert(list, { key = code, comment = comment })
end

-- 从外部词典加载（格式：正确词\t错误读音\t权重\t正确读音）
local function load_dict(path)
    local user_dir = rime_api and rime_api.get_user_data_dir and rime_api.get_user_data_dir() or "."
    local shared_dir = rime_api and rime_api.get_shared_data_dir and rime_api.get_shared_data_dir() or "."

    local f = io.open(user_dir .. "/" .. path, "r")
           or io.open(shared_dir .. "/" .. path, "r")
           or io.open(path, "r")
    if not f then
        return false, "file not found: " .. path
    end

    local count = 0
    for line in f:lines() do
        if not line:match("^#")
           and not line:match("^---")
           and not line:match("^%.%.%.")
           and not line:match("^name:")
           and not line:match("^version:")
           and not line:match("^sort:")
        then
            local text, code, weight, comment = line:match("^(.-)\t(.-)\t(.-)\t(.-)$")
            if text and code and comment then
                add_correction(code, text, comment)
                count = count + 1
            end
        end
    end
    f:close()
    return true, count
end

function M.init(env)
    local config = env.engine.schema.config

    env.name_space = env.name_space:gsub("^%*", "")

    -- style 按实例存，避免多实例互相覆盖
    env.style = config:get_string(env.name_space .. "/style") or "{comment}"

    local delimiter = config:get_string("speller/delimiter")
    if delimiter and #delimiter > 0 and delimiter:sub(1, 1) ~= " " then
        env.delimiter = delimiter:sub(1, 1)
    end

    local fuzzy_enabled = config:get_bool(env.name_space .. "/fuzzy_hint")
    if fuzzy_enabled == nil then fuzzy_enabled = true end
    env.fuzzy_enabled = fuzzy_enabled

    local fuzzy_threshold = config:get_int(env.name_space .. "/fuzzy_threshold")
    env.fuzzy_threshold = fuzzy_threshold or 1

    local clear_on_miss = config:get_bool(env.name_space .. "/clear_on_miss")
    if clear_on_miss == nil then clear_on_miss = false end
    env.clear_on_miss = clear_on_miss

    -- 词典路径（可配置）
    local dict_path = config:get_string(env.name_space .. "/dict") or "cn_dicts/cuoyin.dict.yaml"

    -- 只在路径变化或首次加载时重建表
    if not M._loaded or M._loaded_path ~= dict_path then
        M.corrections = {}
        M.by_text = {}

        -- 1) 先加载内置兜底
        for code, c in pairs(M.builtin_corrections) do
            add_correction(code, c.text, c.comment)
        end

        -- 2) 再加载外部词典（覆盖同 key 的内置项）
        local ok, result = load_dict(dict_path)
        if ok then
            log.info(string.format("[corrector] loaded %s (%s entries)", dict_path, tostring(result)))
        else
            log.warning("[corrector] " .. tostring(result) .. " — using builtin only")
        end

        M._loaded = true
        M._loaded_path = dict_path
    end
end

function M.func(input, env)
    local style = env.style or "{comment}"

    for cand in input:iter() do
        local comment = cand.comment

        if comment and #comment > 0 then
            local raw = comment:match("^［(.-)］$") or comment:match("^%[(.-)%]$") or comment

            if env.delimiter then
                local escaped_delimiter = env.delimiter:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1")
                raw = raw:gsub(escaped_delimiter, " ")
            end

            local key = detone(raw)

            local c = M.corrections[key]
            if c and cand.text == c.text then
                cand:get_genuine().comment = (style:gsub("{comment}", function() return c.comment end))
            else
                local fuzzy_comment = nil
                if env.fuzzy_enabled then
                    local list = M.by_text[cand.text]
                    if list then
                        local best_dist
                        for _, item in ipairs(list) do
                            local dist = edit_distance(key, item.key)
                            if dist > 0 and dist <= env.fuzzy_threshold and (not best_dist or dist < best_dist) then
                                best_dist = dist
                                fuzzy_comment = item.comment
                            end
                        end
                    end
                end

                if fuzzy_comment then
                    cand:get_genuine().comment = (style:gsub("{comment}", function() return "≈" .. fuzzy_comment end))
                elseif env.clear_on_miss then
                    cand:get_genuine().comment = ""
                end
            end
        end

        yield(cand)
    end
end

return M
