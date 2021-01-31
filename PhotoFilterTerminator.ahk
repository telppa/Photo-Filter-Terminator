/*
2021.01.31
修复win7、win8报错的问题。
实现完美圆角效果，但速度较慢，相关代码被注释。
版本号2.2。

2021.01.27
增加没有找到任何 jpg 文件的提示。
修复没有保存图片时，文件夹被错误创建的问题。
版本号2.1。

2021.01.24
绝大部分参数可以自定义。
代码完全重构，实现高性能、低资源占用、低内存增长。
版本号2.0。

2021.01.23
测试加载一张 19.4m 9146x3852 的 jpg 图片
Gdip_CreateBitmapFromHBITMAP(LoadPicture(ImgPath,"GDI+ w1000"))		800ms
Gdip_DrawImage()																									17ms
有摩尔纹
Gdip_CreateBitmapFromFile(ImgPath)																1ms
Gdip_SetInterpolationMode(G, 7)
Gdip_DrawImage()																									981ms
无摩尔纹
Gdip_CreateBitmapFromFile(ImgPath)																1ms
Gdip_SetInterpolationMode(G, 0)
Gdip_DrawImage()																									584ms
无摩尔纹

2021.01.19
初次实现全屏、背景模糊、图片透明、收藏时渐隐渐显效果。
修复小数误差累积导致的图片没有完美对齐的问题。

2021.01.16
收藏图片时使用动画效果。
修复鼠标点击收藏图片后，无法撤销收藏的问题。
修复特殊情况下错误释放资源，导致图片显示白板的问题。

2021.01.15
使用预加载技术，提升载入图片速度。
收藏的图片保留原始相对目录结构。

2019.12.3
LoadPicture()
普通模式，20线程加载20张图片用时6720ms。
普通模式，单线程加载20张图片用时9850ms。
GDI+模式，多线程加载图片必然报错。
GDI+模式，单线程加载20张图片用时5515ms。

Numpad9、滚轮下、PgDn：下一页
Numpad7、滚轮上、PgUp：上一页
小键盘区域的4、5、6、1、2、3 对应相同位置的图片——4对应左上角那张，3对应右下角那张。
也可以直接用鼠标点击图片。

已知bug：
似乎有内存泄露，大约全屏每翻1页涨1-2m内存。
显示提示信息没能跟随窗口。
*刚打开时，以飞快的速度换页，会导致显示失败。
*当本页图片数量与每页显示数量不一致时，显示会失败，此多发于尾页。
*显示图片过程中，如果要实现统一特效，就会反复读取文件。
*如果已经有浏览进度时，又调整了每页显示数量，那么可能会造成超限。
*/
#NoEnv
#SingleInstance Force
SetBatchLines, -1

global 选中图片被收藏到此文件夹下:="MyFavoritePhotos"		;selected images are collected under this folder
, 每行显示数量:=3											; number of pics per row
, 每页几行:=2													; number of rows per page
, 背景图x:=0													; background image x
, 背景图y:=0													; background image y
, 背景图宽:=A_ScreenWidth							; background image width
, 背景图高:=A_ScreenHeight						; background image height
, 横向留白:=背景图高//10								; horizontal white space
, 纵向留白:=背景图高//10								; vertical white space
, 图片被收藏后的透明度:=20							; transparency of the image after it has been collected
, 背景模糊程度:=77										; background blurring level
, 固定使用当页第几张图片作为背景:=1			; fixed use of the specified image on the current page as background
, 随机使用当页某张图片作为背景:=true			; randomly use a certain image on the current page as background
, 图片左对齐、居中、右对齐显示:=2				; 1 = Left-aligned, 2 = centered, 3 = right-aligned images

gosub, 加载作者设置
gosub, 加载文件
gosub, 恢复进度
gosub, 创建界面
OnMessage(0x201, "WM_LBUTTONDOWN")	; 监测鼠标点击
资源分配()
首次显示并预加载()
return

加载作者设置:
	; 有内存盘就把收藏文件夹放内存盘里
	if (FileExist("R:"))
		选中图片被收藏到此文件夹下:="R:\" 选中图片被收藏到此文件夹下
	else
		选中图片被收藏到此文件夹下:=A_ScriptDir "\" 选中图片被收藏到此文件夹下	

	; 为用户自定义变量限制范围
	每行显示数量:=Max(每行显示数量, 1)
	, 每页几行:=Max(每页几行, 1)
	, 背景图x:=Max(背景图x, 0)
	, 背景图y:=Max(背景图y, 0)
	, 背景图宽:=Max(背景图宽, 300)
	, 背景图高:=Max(背景图高, 300)
	, 横向留白:=Max(横向留白, 0)
	, 纵向留白:=Max(纵向留白, 0)
	; 因为图片透明度为0后，会导致A_Gui没有值，造成鼠标点击图片位置没法恢复图片，所以限制一个最小值
	, 图片被收藏后的透明度:=Max(图片被收藏后的透明度, 1)
	, 背景模糊程度:=Min(背景模糊程度, 255)
	, 软件名:="图片筛选机"
	, 版本号:=2.2

	; 申明一些以后会用到的超级全局变量
	global 全部文件列表, 当前页数, 每页显示数量, 最大页数, 末页显示数量, 坐标合集, 资源, 点击的是第几张图片
return

加载文件:
	; 加载全部jpg文件列表
	显示提示信息("加载图片列表……")
	全部文件列表:=[]
	loop, Files, *.jpg, R
		; 注意这里的文件路径是相对路径，这是为了后面收藏模块解析时可以保留文件夹结构。
		全部文件列表.Push(A_LoopFileFullPath)
	if (!全部文件列表.MaxIndex())
	{
		MsgBox, No *.jpg files found!
		ExitApp
	}
return

恢复进度:
	; 恢复到上次退出时浏览的位置
	显示提示信息("恢复筛选进度……")
	FileRead, 当前页数, PhotoFilterTerminator.txt
return

创建界面:
	; ======================================================================
	; 以下参数都靠上面的用户自定义值计算
	每页显示数量:=每行显示数量*每页几行
	, 最大页数:=全部文件列表.MaxIndex()//每页显示数量+1		; //表示向下舍除，例如5//3=1，所以最后要+1
	; 原来每页显示10张，共10页，浏览进度是第6页。此时退出并修改设置为每页显示20张，进入后就会白板，所以要限制不超过最大页数。
	, 当前页数:=当前页数="" ? 1 : Min(当前页数, 最大页数)
	, 末页显示数量:=Mod(全部文件列表.MaxIndex(), 每页显示数量)=0 ? 每行显示数量 : Mod(全部文件列表.MaxIndex(), 每页显示数量)
	; 务必要取整，不然总会有1-2px的偏差
	, 小图宽:=(背景图宽-横向留白)//每行显示数量
	, 小图高:=(背景图高-纵向留白)//每页几行

	; 设计上将显示分为了两层，底下是背景层，上面是图片层，图片层是背景层的子窗口，永远显示在背景层上面
	; 背景层 必须使用 +E0x80000 选项。同时置顶，去掉标题栏，去掉任务栏显示，模式对话框设为子窗口
	Gui, 背景图: +E0x80000 +AlwaysOnTop -Caption +ToolWindow +OwnDialogs +Hwnd背景图句柄
	Gui, 背景图: Show, , %软件名% v%版本号%

	; 图片层 每张图片单独创建一个 gui 以便获得句柄
	loop, % 每页显示数量
	{
		; 大坑！父窗口必须先于子窗口显示出来，否则子窗口内容不可见！
		Gui, 图%A_Index%: +E0x80000 +AlwaysOnTop -Caption +ToolWindow +Hwnd图%A_Index%句柄 +Owner背景图
		Gui, 图%A_Index%: Show, NA
	}

	坐标合集:=[]
	, 坐标合集["背景图x"]:=背景图x, 坐标合集["背景图y"]:=背景图y
	, 坐标合集["背景图w"]:=背景图宽, 坐标合集["背景图h"]:=背景图高
	, 坐标合集["背景图句柄"]:=背景图句柄
	loop, % 每页显示数量
	{
		当前所处行:=Ceil(A_Index/每行显示数量)
		, 当前所处列:=Mod(A_Index, 每行显示数量)=0 ? 每行显示数量 : Mod(A_Index, 每行显示数量)
		, 坐标合集["图" A_Index "x"]:=当前所处列*(横向留白//(每行显示数量+1))+(当前所处列-1)*小图宽
		, 坐标合集["图" A_Index "y"]:=当前所处行*(纵向留白//(每页几行+1))+(当前所处行-1)*小图高
		, 坐标合集["图" A_Index "w"]:=小图宽
		, 坐标合集["图" A_Index "h"]:=小图高
		, 坐标合集["图" A_Index "句柄"]:=图%A_Index%句柄
	}

	; Start gdi+
	if !pToken := Gdip_Startup()
	{
		MsgBox, 48, gdiplus error!, Gdiplus failed to start. Please ensure you have gdiplus on your system
		ExitApp
	}
	OnExit, GdipExit
return

背景图GuiClose:
背景图GuiEscape:
GdipExit:
	FileDelete, PhotoFilterTerminator.txt
	FileAppend, %当前页数%, PhotoFilterTerminator.txt
	资源回收()
	Gdip_Shutdown(pToken)
	ExitApp
return

资源分配()
{
	资源:=[]
	; 本页_图1_hbm		本页_图1_hdc		本页_图1_obm		本页_图1_G
	; 下一页_图1_hbm 下一页_图1_hdc 下一页_图1_obm 下一页_图1_G
	; 上一页_图1_hbm 上一页_图1_hdc 上一页_图1_obm 上一页_图1_G
	; 创建类似上述这些变量供缓存时使用
	; 由于这些变量里的值都是整数的地址，所以可以这样存着。
	for k, v in 缓存标记:=["本页", "下一页", "上一页"]
		loop, % 每页显示数量+1		; 要把背景图的资源也分配了，所以得 “每页显示数量+1”
		{
			; 构造资源对象名称里用的字符串
			编号:=(A_Index=每页显示数量+1) ? "背景图": "图" A_Index
			, DIB宽:=坐标合集[编号 "w"]
			, DIB高:=坐标合集[编号 "h"]
			, hbm:=v "_" 编号 "_hbm"
			, hdc:=v "_" 编号 "_hdc"
			, obm:=v "_" 编号 "_obm"
			, G:=v "_" 编号 "_G"

			; 经过上一段对名称的构造，这里看起来就清晰多了
			, 资源[hbm] := CreateDIBSection(DIB宽, DIB高)
			, 资源[hdc] := CreateCompatibleDC()
			, 资源[obm] := SelectObject(资源[hdc], 资源[hbm])
			, 资源[G] := Gdip_GraphicsFromHDC(资源[hdc])

			; 根据测试，不管是放大还是缩小，尤其是缩小，模式0是最快效果又还不错的
			, Gdip_SetInterpolationMode(资源[G], 0)
			; 抗锯齿模式
			, Gdip_SetSmoothingMode(资源[G], 4)
			; 这是画出完美圆角矩形的关键设置
			, Gdip_SetPixelOffsetMode(资源[G], 2)
		}
}

首次显示并预加载()
{
	Critical, On
	加载图片到DC(当前页数, "本页")
	显示提示信息(当前页数 "/" 最大页数)
	渐变显示整页DC()
	加载图片到DC(当前页数+1, "下一页")
	加载图片到DC(当前页数-1, "上一页")
	Critical, Off
}

翻页显示并预加载(翻页方向, 缓存标记)
{
	Critical, On
	当前页数:=当前页数+翻页方向
	移动整页DC(翻页方向)												; 将DC往后翻一页
	显示提示信息(当前页数 "/" 最大页数)
	渐变显示整页DC()													; 显示DC
	加载图片到DC(当前页数+翻页方向, 缓存标记)			; 预加载
	Critical, Off
}

加载图片到DC(当前页数, 缓存标记)
{
	; 超出最大最小页数时，直接返回空值
	if (当前页数>最大页数)
		return, false
	else if (当前页数<1)
		return, false
	; 用于修正末页数量由于和其它页不同，导致的显示不正确
	else if (当前页数=最大页数)
		本页显示数量:=末页显示数量
	else
		本页显示数量:=每页显示数量

	背景页:=Min(固定使用当页第几张图片作为背景, 本页显示数量)
	if (随机使用当页某张图片作为背景)
		Random, 背景页, 1, % 本页显示数量

	; 把待显示内容存到对应的dc里
	loop, % 每页显示数量
	{
		ImgPath:=全部文件列表[(当前页数-1)*每页显示数量+A_Index]
		; 这里让它自然的加载空值，就可以在末页时正确显示
		pBitmap := Gdip_CreateBitmapFromFile(ImgPath)

		框w:=坐标合集["图" A_Index "w"], 框h:=坐标合集["图" A_Index "h"], 框比例:=框w/框h
		, Gdip_GetImageDimensions(pBitmap, 图片实际w, 图片实际h), 图片比例:=图片实际w/图片实际h
		; 图比框更横
		if (图片比例>=框比例)
		{
			图片显示w:=框w
			图片显示h:=图片显示w//图片比例
			图片显示x:=0
			图片显示y:=(框h-图片显示h)//2
		}
		else
		{
			图片显示h:=框h
			图片显示w:=Round(图片显示h*图片比例)
			if (图片左对齐、居中、右对齐显示=1)
				图片显示x:=0
			else if (图片左对齐、居中、右对齐显示=3)
				图片显示x:=框w-图片显示w
			else	
				图片显示x:=(框w-图片显示w)//2
			图片显示y:=0
		}
		; 资源[缓存标记 "_图" A_Index "_G"] ----> 资源["本页_图1_G"]
		Gdip_GraphicsClear(资源[缓存标记 "_图" A_Index "_G"])		; 先清空画布再画图
		; pBitmap:=Gdip_ResizeBitmap(pBitmap, 图片显示w, 图片显示h, 0)
		; pBrush:= Gdip_CreateTextureBrush(pBitmap, 0)
		; 想象一个表面有图案的滚筒，图案的0点与画布0点永恒绑定。
		; 当我们将画布50点作为起点作画时，显然图案也会从50点开始滚出。
		; 所以 Gdip_PathGradientTranslateTransform() 的作用就是 ——
		; 当我们将画布50点作为起点作画时，图案可以从指定点（这里是0点）开始滚出。
		; Gdip_PathGradientTranslateTransform(pBrush, 图片显示x, 图片显示y)
		; Gdip_FillRoundedRectanglePath(资源[缓存标记 "_图" A_Index "_G"], pBrush, 图片显示x, 图片显示y, 图片显示w, 图片显示h, 4)
		; Gdip_DeleteBrush(pBrush)
		Gdip_DrawImage(资源[缓存标记 "_图" A_Index "_G"], pBitmap, 图片显示x, 图片显示y, 图片显示w, 图片显示h, 0, 0, 图片实际w, 图片实际h)

		if (A_Index=背景页)		; 将背景图进行模糊处理
		{
			; 因为模糊处理非常耗时间，所以先把图片缩小到待显示的1/4大小，进行模糊，再放大，就可以在效果差异不大的情况下加速
			pBitmap:=Gdip_ResizeBitmap(pBitmap, 坐标合集["背景图w"]//2, 坐标合集["背景图h"]//2, 0)
			, pEffect := Gdip_CreateEffect(1, 背景模糊程度, 0, 0)		; 创建模糊效果
			, Gdip_ApplySpecialFixedBlur(pBitmap, 背景模糊程度, pEffect)		; 应用模糊效果
			, pBitmap:=Gdip_ResizeBitmap(pBitmap, 坐标合集["背景图w"], 坐标合集["背景图h"], 0)		; 把背景图放大回去
			, Gdip_GraphicsClear(资源[缓存标记 "_背景图_G"])		; 先清空画布，再画图
			, Gdip_DrawImageFast(资源[缓存标记 "_背景图_G"], pBitmap)
			, Gdip_DisposeEffect(pEffect)		; 释放特效资源
		}
		; 释放资源
		Gdip_DisposeImage(pBitmap)
	}
	return, true
}

Gdip_ApplySpecialFixedBlur(zBitmap, radius, pEffect, previewMode:=0) {
	if (!pEffect || !zBitmap)
	{
		 return, false
	}

	if (radius>19 || previewMode=1)
	{
		 Gdip_BitmapApplyEffect(zBitmap, pEffect)
		 return, true
	}

	if (radius=19)
		 radius += 18
	else if (radius=18)
		 radius += 15
	else if (radius=17)
		 radius += 12
	else if (radius=16)
		 radius += 10
	else if (radius=15)
		 radius += 8
	else if (radius=14)
		 radius += 6
	else if (radius=13)
		 radius += 4
	else if (radius=12)
		 radius += 2
	else if (radius=11)
		 radius += 1

	if (radius<=1)
		 radius := 2

	zA := Gdip_CreateEffect(1, radius//2, 0, 0)
	zB := Gdip_CreateEffect(1, radius//2, 0, 0)
	Gdip_ImageRotateFlip(zBitmap, 1)
	Gdip_BitmapApplyEffect(zBitmap, zA)
	Gdip_ImageRotateFlip(zBitmap, 3)
	Gdip_BitmapApplyEffect(zBitmap, zB)
	Gdip_DisposeEffect(zA)
	Gdip_DisposeEffect(zB)
	return, true
}

渐变显示整页DC(缓存标记:="本页")
{
	; 显示背景
	UpdateLayeredWindow(坐标合集["背景图句柄"], 资源[缓存标记 "_背景图_hdc"]
	, 坐标合集["背景图x"], 坐标合集["背景图y"], 坐标合集["背景图w"], 坐标合集["背景图h"])

	; 显示图片
	目标透明度:=[]
	loop, % 每页显示数量
		目标透明度[A_Index]:=检查图片是否已被收藏(A_Index) ? 图片被收藏后的透明度 : 255
	; 自定义一个透明度渐变表，注意必须从0开始，否则“图片被收藏后的透明度”值过小时，会直接在循环中被跳过，图片刷新不出来
	for k, v in [0,10,20,30,50,80,130,210,255]
	{
		loop, % 每页显示数量
		{
				UpdateLayeredWindow(坐标合集["图" A_Index "句柄"], 资源[缓存标记 "_图" A_Index "_hdc"]
				, 坐标合集["图" A_Index "x"], 坐标合集["图" A_Index "y"]
				, 坐标合集["图" A_Index "w"], 坐标合集["图" A_Index "h"], Min(v, 目标透明度[A_Index]))
		}
		Sleep, 20
	}
}

渐变显示单张DC(图片在当页的编号, 显或隐, 缓存标记:="本页")
{
	if (显或隐=1)
	{
		; 渐显
		while (透明度<255)
		{
			透明度:=Min(图片被收藏后的透明度+A_Index*10, 255)
			UpdateLayeredWindow(坐标合集["图" 图片在当页的编号 "句柄"], 资源[缓存标记 "_图" 图片在当页的编号 "_hdc"]
			, 坐标合集["图" 图片在当页的编号 "x"], 坐标合集["图" 图片在当页的编号 "y"]
			, 坐标合集["图" 图片在当页的编号 "w"], 坐标合集["图" 图片在当页的编号 "h"], 透明度)
			Sleep, 15
		}
	}
	else
	{
		透明度:=255
		; 渐隐
		while (透明度>图片被收藏后的透明度)
		{
			透明度:=Max(255-A_Index*10, 图片被收藏后的透明度)
			UpdateLayeredWindow(坐标合集["图" 图片在当页的编号 "句柄"], 资源[缓存标记 "_图" 图片在当页的编号 "_hdc"]
			, 坐标合集["图" 图片在当页的编号 "x"], 坐标合集["图" 图片在当页的编号 "y"]
			, 坐标合集["图" 图片在当页的编号 "w"], 坐标合集["图" 图片在当页的编号 "h"], 透明度)
			Sleep, 15
		}
	}
}

; 返回1代表图片已经被收藏，返回0代表图片没有被收藏
检查图片是否已被收藏(图片在当页的编号, ByRef 选中图片路径:="", ByRef OutFileName:="", ByRef OutDir:="")
{
	选中图片路径:="", OutFileName:="", OutDir:=""		; ByRef 导致变量值是有记忆的，所以进来以后先清空一遍
	, 选中图片路径:=全部文件列表[(当前页数-1)*每页显示数量+图片在当页的编号]
	SplitPath, 选中图片路径, OutFileName, OutDir		; 注意图片路径实际是相对路径，所以这里 OutDir 直接就是目录名，而不是整个路径。
	if (OutDir!="")
		OutDir:=选中图片被收藏到此文件夹下 "\" OutDir "\"
	else
		OutDir:=选中图片被收藏到此文件夹下 "\"

	OutFileName:=OutDir 删除不能被用于创建文件或文件夹的字符(OutFileName)
	if (!FileExist(OutFileName))
		return, false
	else
		return, true
}

移动整页DC(移动方向)
{
	temp:=[]
	for k, v in 资源
	{
		; 移动方向为1，代表往后翻页
		if (移动方向=1)
		{
			if (InStr(k, "上一页"))
				temp[StrReplace(k, "上一页_", "下一页_")]:=v
			else if (InStr(k, "本页"))
				temp[StrReplace(k, "本页_", "上一页_")]:=v
			else if (InStr(k, "下一页"))
				temp[StrReplace(k, "下一页_", "本页_")]:=v
		}
		; 移动方向为-1，代表往前翻页
		else if (移动方向=-1)
		{
			if (InStr(k, "下一页"))
				temp[StrReplace(k, "下一页_", "上一页_")]:=v
			else if (InStr(k, "本页"))
				temp[StrReplace(k, "本页_", "下一页_")]:=v
			else if (InStr(k, "上一页"))
				temp[StrReplace(k, "上一页_", "本页_")]:=v
		}
		else
			return, false
	}
	资源:=temp.Clone()
	return, true
}

资源回收()
{
	for k, v in 资源
		if (SubStr(k, -3, 4)="_hbm")
		{
			; n 的值是去掉末尾4位的剩余部分 例如 “本页_图6_hbm” n = “本页_图6”
			n:=SubStr(k, 1, -4)
			Gdip_DeleteGraphics(资源[n "_G"])
			SelectObject(资源[n "_hdc"], 资源[n "_obm"])
			DeleteObject(资源[n "_hbm"])
			DeleteDC(资源[n "_hdc"])
		}
}

WM_LBUTTONDOWN()
{
	; 有一点需要注意，当图片透明度为0时，这里的 A_Gui 是没有值的。
	; 所以渐隐一张图片时，最好隐成半透明。
	if (A_Gui!="背景图")
	{
		; SubStr 将 “图1” 变换成 “1”
		点击的是第几张图片:=SubStr(A_Gui, 0, 1)
		SetTimer, 图片被点击, -1
	}
}

#If WinActive(软件名)
; 笔记本电脑很多没有小键盘区域，所以在主区域也增加一组键盘设置
; 默认只预设了 横*竖 3*2 的图片布局 的键盘设置
图片被点击:
j::
k::
l::
m::
,::
.::
Numpad4::
Numpad5::
Numpad6::
Numpad1::
Numpad2::
Numpad3::
	选中的是第几张图片:=""
	; 如果是用鼠标选中的
	if (点击的是第几张图片)
	{
		选中的是第几张图片:=点击的是第几张图片
		, 点击的是第几张图片:=""
	}
	else
	{
		; 如果是用键盘选中的
		switch, A_ThisHotkey
		{
			case, "Numpad4":选中的是第几张图片:=1
			case, "Numpad5":选中的是第几张图片:=2
			case, "Numpad6":选中的是第几张图片:=3
			case, "Numpad1":选中的是第几张图片:=4
			case, "Numpad2":选中的是第几张图片:=5
			case, "Numpad3":选中的是第几张图片:=6
			case, "j":选中的是第几张图片:=1
			case, "k":选中的是第几张图片:=2
			case, "l":选中的是第几张图片:=3
			case, "m":选中的是第几张图片:=4
			case, ",":选中的是第几张图片:=5
			case, ".":选中的是第几张图片:=6
		}
	}
	gosub, 收藏图片
return

收藏图片:
	if (检查图片是否已被收藏(选中的是第几张图片, 源, 目标, 目标目录))
	{
		; 渐显
		渐变显示单张DC(选中的是第几张图片, 1)
		FileDelete, % 目标
	}
	else
	{
		; 渐隐
		渐变显示单张DC(选中的是第几张图片, 0)
		FileCreateDir, % 目标目录		; 先创建目录，不然文件不一定能成功复制 
		FileCopy, % 源, % 目标
	}
return

Numpad9::
WheelDown::
PgDn::
/::
	if (当前页数>=最大页数)
		显示提示信息("已到末页")
	else
		翻页显示并预加载(1, "下一页")
return

Numpad7::
WheelUp::
PgUp::
n::
	if (当前页数<=1)
		显示提示信息("已到首页")
	else
		翻页显示并预加载(-1, "上一页")
return
#If

显示提示信息(文本:="")
{
文本:=RTrim(文本, " `t`r`n`v`f")
if 文本
{
WinGetPos,,,,th,ahk_class Shell_TrayWnd
SysGet, vw, 78
SysGet, vh, 79
StrReplace(文本, "`n", "`n", n)
CoordMode, ToolTip, Screen
ToolTip, %文本%, % vw-30, % vh-(th+8+(n+1)*16.846)
}
else
ToolTip
}

删除不能被用于创建文件或文件夹的字符(str)
{
StringReplace, str, str, `\, , All
StringReplace, str, str, `/, , All
StringReplace, str, str, `:, , All
StringReplace, str, str, `*, , All
StringReplace, str, str, `?, , All
StringReplace, str, str, `", , All
StringReplace, str, str, `<, , All
StringReplace, str, str, `>, , All
StringReplace, str, str, `|, , All
StringReplace, str, str, `r, , All
StringReplace, str, str, `n, , All
Loop
{
if (SubStr(str, 0, 1)=".")
StringTrimRight, str, str, 1
else
break
}
return, str
}

; ========== The following are all Gdip library =========
; Gdip_All.ahk - GDI+ library compilation of user contributed GDI+ functions
; made by Marius Șucan: https://github.com/marius-sucan/AHK-GDIp-Library-Compilation
; a fork from: https://github.com/mmikeww/AHKv2-Gdip
; based on https://github.com/tariqporter/Gdip
UpdateLayeredWindow(hwnd, hdc, x:="", y:="", w:="", h:="", Alpha:=255) {
Static Ptr := "UPtr"
if ((x != "") && (y != ""))
VarSetCapacity(pt, 8), NumPut(x, pt, 0, "UInt"), NumPut(y, pt, 4, "UInt")
if (w = "") || (h = "")
GetWindowRect(hwnd, W, H)
return DllCall("UpdateLayeredWindow"
, Ptr, hwnd
, Ptr, 0
, Ptr, ((x = "") && (y = "")) ? 0 : &pt
, "int64*", w|h<<32
, Ptr, hdc
, "int64*", 0
, "uint", 0
, "UInt*", Alpha<<16|1<<24
, "uint", 2)
}
BitBlt(ddc, dx, dy, dw, dh, sdc, sx, sy, raster:="") {
Static Ptr := "UPtr"
return DllCall("gdi32\BitBlt"
, Ptr, dDC
, "int", dX, "int", dY
, "int", dW, "int", dH
, Ptr, sDC
, "int", sX, "int", sY
, "uint", Raster ? Raster : 0x00CC0020)
}
StretchBlt(ddc, dx, dy, dw, dh, sdc, sx, sy, sw, sh, Raster:="") {
Static Ptr := "UPtr"
return DllCall("gdi32\StretchBlt"
, Ptr, ddc
, "int", dX, "int", dY
, "int", dW, "int", dH
, Ptr, sdc
, "int", sX, "int", sY
, "int", sW, "int", sH
, "uint", Raster ? Raster : 0x00CC0020)
}
SetStretchBltMode(hdc, iStretchMode:=4) {
return DllCall("gdi32\SetStretchBltMode"
, "UPtr", hdc
, "int", iStretchMode)
}
SetImage(hwnd, hBitmap) {
If (!hBitmap || !hwnd)
Return
Static Ptr := "UPtr"
E := DllCall("SendMessage", Ptr, hwnd, "UInt", 0x172, "UInt", 0x0, Ptr, hBitmap )
DeleteObject(E)
return E
}
SetSysColorToControl(hwnd, SysColor:=15) {
Static Ptr := "UPtr"
GetWindowRect(hwnd, W, H)
bc := DllCall("GetSysColor", "Int", SysColor, "UInt")
pBrushClear := Gdip_BrushCreateSolid(0xff000000 | (bc >> 16 | bc & 0xff00 | (bc & 0xff) << 16))
pBitmap := Gdip_CreateBitmap(w, h)
G := Gdip_GraphicsFromImage(pBitmap)
Gdip_FillRectangle(G, pBrushClear, 0, 0, w, h)
hBitmap := Gdip_CreateHBITMAPFromBitmap(pBitmap)
SetImage(hwnd, hBitmap)
Gdip_DeleteBrush(pBrushClear)
Gdip_DeleteGraphics(G)
Gdip_DisposeImage(pBitmap)
DeleteObject(hBitmap)
return 0
}
Gdip_BitmapFromScreen(Screen:=0, Raster:="") {
hhdc := 0
Static Ptr := "UPtr"
if (Screen = 0)
{
_x := DllCall("GetSystemMetrics", "Int", 76 )
_y := DllCall("GetSystemMetrics", "Int", 77 )
_w := DllCall("GetSystemMetrics", "Int", 78 )
_h := DllCall("GetSystemMetrics", "Int", 79 )
} else if (SubStr(Screen, 1, 5) = "hwnd:")
{
hwnd := SubStr(Screen, 6)
if !WinExist("ahk_id " hwnd)
return -2
GetWindowRect(hwnd, _w, _h)
_x := _y := 0
hhdc := GetDCEx(hwnd, 3)
} else if IsInteger(Screen)
{
M := GetMonitorInfo(Screen)
_x := M.Left, _y := M.Top, _w := M.Right-M.Left, _h := M.Bottom-M.Top
} else
{
S := StrSplit(Screen, "|")
_x := S[1], _y := S[2], _w := S[3], _h := S[4]
}
if (_x = "") || (_y = "") || (_w = "") || (_h = "")
return -1
chdc := CreateCompatibleDC(), hbm := CreateDIBSection(_w, _h, chdc)
obm := SelectObject(chdc, hbm), hhdc := hhdc ? hhdc : GetDC()
BitBlt(chdc, 0, 0, _w, _h, hhdc, _x, _y, Raster)
ReleaseDC(hhdc)
pBitmap := Gdip_CreateBitmapFromHBITMAP(hbm)
SelectObject(chdc, obm), DeleteObject(hbm), DeleteDC(hhdc), DeleteDC(chdc)
return pBitmap
}
Gdip_BitmapFromHWND(hwnd, clientOnly:=0) {
if DllCall("IsIconic", "ptr", hwnd)
DllCall("ShowWindow", "ptr", hwnd, "int", 4)
Static Ptr := "UPtr"
thisFlag := 0
If (clientOnly=1)
{
VarSetCapacity(rc, 16, 0)
DllCall("GetClientRect", "ptr", hwnd, "ptr", &rc)
Width := NumGet(rc, 8, "int")
Height := NumGet(rc, 12, "int")
thisFlag := 1
} Else GetWindowRect(hwnd, Width, Height)
hbm := CreateDIBSection(Width, Height)
hdc := CreateCompatibleDC(), obm := SelectObject(hdc, hbm)
PrintWindow(hwnd, hdc, 2 + thisFlag)
pBitmap := Gdip_CreateBitmapFromHBITMAP(hbm)
SelectObject(hdc, obm), DeleteObject(hbm), DeleteDC(hdc)
return pBitmap
}
CreateRectF(ByRef RectF, x, y, w, h) {
VarSetCapacity(RectF, 16)
NumPut(x, RectF, 0, "float"), NumPut(y, RectF, 4, "float")
NumPut(w, RectF, 8, "float"), NumPut(h, RectF, 12, "float")
}
CreateRect(ByRef Rect, x, y, x2, y2) {
VarSetCapacity(Rect, 16)
NumPut(x, Rect, 0, "uint"), NumPut(y, Rect, 4, "uint")
NumPut(x2, Rect, 8, "uint"), NumPut(y2, Rect, 12, "uint")
}
CreateSizeF(ByRef SizeF, w, h) {
VarSetCapacity(SizeF, 8)
NumPut(w, SizeF, 0, "float")
NumPut(h, SizeF, 4, "float")
}
CreatePointF(ByRef PointF, x, y) {
VarSetCapacity(PointF, 8)
NumPut(x, PointF, 0, "float")
NumPut(y, PointF, 4, "float")
}
CreatePointsF(ByRef PointsF, inPoints) {
Points := StrSplit(inPoints, "|")
PointsCount := Points.Length()
VarSetCapacity(PointsF, 8 * PointsCount, 0)
for eachPoint, Point in Points
{
Coord := StrSplit(Point, ",")
NumPut(Coord[1], &PointsF, 8*(A_Index-1), "float")
NumPut(Coord[2], &PointsF, (8*(A_Index-1))+4, "float")
}
Return PointsCount
}
CreateDIBSection(w, h, hdc:="", bpp:=32, ByRef ppvBits:=0, Usage:=0, hSection:=0, Offset:=0) {
Static Ptr := "UPtr"
hdc2 := hdc ? hdc : GetDC()
VarSetCapacity(bi, 40, 0)
NumPut(40, bi, 0, "uint")
NumPut(w, bi, 4, "uint")
NumPut(h, bi, 8, "uint")
NumPut(1, bi, 12, "ushort")
NumPut(bpp, bi, 14, "ushort")
NumPut(0, bi, 16, "uInt")
hbm := DllCall("CreateDIBSection"
, Ptr, hdc2
, Ptr, &bi
, "uint", Usage
, "UPtr*", ppvBits
, Ptr, hSection
, "uint", OffSet, Ptr)
if !hdc
ReleaseDC(hdc2)
return hbm
}
PrintWindow(hwnd, hdc, Flags:=2) {
If ((A_OSVersion="WIN_XP" || A_OSVersion="WIN_2000" || A_OSVersion="WIN_2003") && flags=2)
flags := 0
return DllCall("PrintWindow", "UPtr", hwnd, "UPtr", hdc, "uint", Flags)
}
DestroyIcon(hIcon) {
return DllCall("DestroyIcon", "UPtr", hIcon)
}
GetIconDimensions(hIcon, ByRef Width, ByRef Height) {
Static Ptr := "UPtr"
Width := Height := 0
VarSetCapacity(ICONINFO, size := 16 + 2 * A_PtrSize, 0)
if !DllCall("user32\GetIconInfo", Ptr, hIcon, Ptr, &ICONINFO)
return -1
hbmMask := NumGet(&ICONINFO, 16, Ptr)
hbmColor := NumGet(&ICONINFO, 16 + A_PtrSize, Ptr)
VarSetCapacity(BITMAP, size, 0)
if DllCall("gdi32\GetObject", Ptr, hbmColor, "Int", size, Ptr, &BITMAP)
{
Width := NumGet(&BITMAP, 4, "Int")
Height := NumGet(&BITMAP, 8, "Int")
}
if !DeleteObject(hbmMask)
return -2
if !DeleteObject(hbmColor)
return -3
return 0
}
PaintDesktop(hdc) {
return DllCall("PaintDesktop", "UPtr", hdc)
}
CreateCompatibleDC(hdc:=0) {
return DllCall("CreateCompatibleDC", "UPtr", hdc)
}
SelectObject(hdc, hgdiobj) {
Static Ptr := "UPtr"
return DllCall("SelectObject", Ptr, hdc, Ptr, hgdiobj)
}
DeleteObject(hObject) {
return DllCall("DeleteObject", "UPtr", hObject)
}
GetDC(hwnd:=0) {
return DllCall("GetDC", "UPtr", hwnd)
}
GetDCEx(hwnd, flags:=0, hrgnClip:=0) {
Static Ptr := "UPtr"
return DllCall("GetDCEx", Ptr, hwnd, Ptr, hrgnClip, "int", flags)
}
ReleaseDC(hdc, hwnd:=0) {
Static Ptr := "UPtr"
return DllCall("ReleaseDC", Ptr, hwnd, Ptr, hdc)
}
DeleteDC(hdc) {
return DllCall("DeleteDC", "UPtr", hdc)
}
Gdip_LibraryVersion() {
return 1.45
}
Gdip_LibrarySubVersion() {
return 1.85
}
Gdip_BitmapFromBRA(ByRef BRAFromMemIn, File, Alternate := 0) {
pBitmap := 0
pStream := 0
If !(BRAFromMemIn)
Return -1
Headers := StrSplit(StrGet(&BRAFromMemIn, 256, "CP0"), "`n")
Header := StrSplit(Headers.1, "|")
If (Header.Length() != 4) || (Header.2 != "BRA!")
Return -2
_Info := StrSplit(Headers.2, "|")
If (_Info.Length() != 3)
Return -3
OffsetTOC := StrPut(Headers.1, "CP0") + StrPut(Headers.2, "CP0")
OffsetData := _Info.2
SearchIndex := Alternate ? 1 : 2
TOC := StrGet(&BRAFromMemIn + OffsetTOC, OffsetData - OffsetTOC - 1, "CP0")
RX1 := A_AhkVersion < "2" ? "mi`nO)^" : "mi`n)^"
Offset := Size := 0
If RegExMatch(TOC, RX1 . (Alternate ? File "\|.+?" : "\d+\|" . File) . "\|(\d+)\|(\d+)$", FileInfo) {
Offset := OffsetData + FileInfo.1
Size := FileInfo.2
}
If (Size=0)
Return -4
hData := DllCall("GlobalAlloc", "UInt", 2, "UInt", Size, "UPtr")
pData := DllCall("GlobalLock", "Ptr", hData, "UPtr")
DllCall("RtlMoveMemory", "Ptr", pData, "Ptr", &BRAFromMemIn + Offset, "Ptr", Size)
DllCall("GlobalUnlock", "Ptr", hData)
DllCall("Ole32.dll\CreateStreamOnHGlobal", "Ptr", hData, "Int", 1, "PtrP", pStream)
pBitmap := Gdip_CreateBitmapFromStream(pStream)
ObjRelease(pStream)
Return pBitmap
}
Gdip_BitmapToBase64(pBitmap, Format, Quality:=90) {
Format := "none." Format
Return Gdip_SaveBitmapToFile(pBitmap, Format, Quality, 1)
}
Gdip_BitmapFromBase64(ByRef Base64) {
Static Ptr := "UPtr"
pBitmap := 0
DecLen := 0
if !(DllCall("crypt32\CryptStringToBinary", Ptr, &Base64, "UInt", 0, "UInt", 0x01, Ptr, 0, "UIntP", DecLen, Ptr, 0, Ptr, 0))
return -1
VarSetCapacity(Dec, DecLen, 0)
if !(DllCall("crypt32\CryptStringToBinary", Ptr, &Base64, "UInt", 0, "UInt", 0x01, Ptr, &Dec, "UIntP", DecLen, Ptr, 0, Ptr, 0))
return -2
if !(pStream := DllCall("shlwapi\SHCreateMemStream", Ptr, &Dec, "UInt", DecLen, "UPtr"))
return -3
pBitmap := Gdip_CreateBitmapFromStream(pStream, 1)
ObjRelease(pStream)
return pBitmap
}
Gdip_CreateBitmapFromStream(pStream, useICM:=0) {
pBitmap := 0
function2call := (useICM=1) ? "ICM" : ""
gdipLastError := DllCall("gdiplus\GdipCreateBitmapFromStream" function2call, "UPtr", pStream, "PtrP", pBitmap)
Return pBitmap
}
Gdip_DrawRectangle(pGraphics, pPen, x, y, w, h) {
If (!pGraphics || !pPen || !w || !h)
Return 2
Return DllCall("gdiplus\GdipDrawRectangle", "UPtr", pGraphics, "UPtr", pPen, "float", x, "float", y, "float", w, "float", h)
}
Gdip_DrawRoundedRectangle(pGraphics, pPen, x, y, w, h, r) {
If (!pGraphics || !pPen || !w || !h)
Return 2
Gdip_SetClipRect(pGraphics, x-r, y-r, 2*r, 2*r, 4)
Gdip_SetClipRect(pGraphics, x+w-r, y-r, 2*r, 2*r, 4)
Gdip_SetClipRect(pGraphics, x-r, y+h-r, 2*r, 2*r, 4)
Gdip_SetClipRect(pGraphics, x+w-r, y+h-r, 2*r, 2*r, 4)
_E := Gdip_DrawRectangle(pGraphics, pPen, x, y, w, h)
Gdip_ResetClip(pGraphics)
Gdip_SetClipRect(pGraphics, x-(2*r), y+r, w+(4*r), h-(2*r), 4)
Gdip_SetClipRect(pGraphics, x+r, y-(2*r), w-(2*r), h+(4*r), 4)
Gdip_DrawEllipse(pGraphics, pPen, x, y, 2*r, 2*r)
Gdip_DrawEllipse(pGraphics, pPen, x+w-(2*r), y, 2*r, 2*r)
Gdip_DrawEllipse(pGraphics, pPen, x, y+h-(2*r), 2*r, 2*r)
Gdip_DrawEllipse(pGraphics, pPen, x+w-(2*r), y+h-(2*r), 2*r, 2*r)
Gdip_ResetClip(pGraphics)
return _E
}
Gdip_DrawRoundedRectangle2(pGraphics, pPen, x, y, w, h, r, Angle:=0) {
If (!pGraphics || !pPen || !w || !h)
Return 2
penWidth := Gdip_GetPenWidth(pPen)
pw := penWidth / 2
if (w <= h && (r + pw > w / 2))
{
r := (w / 2 > pw) ? w / 2 - pw : 0
} else if (h < w && r + pw > h / 2)
{
r := (h / 2 > pw) ? h / 2 - pw : 0
} else if (r < pw / 2)
{
r := pw / 2
}
r2 := r * 2
path1 := Gdip_CreatePath(0)
Gdip_AddPathArc(path1, x + pw, y + pw, r2, r2, 180, 90)
Gdip_AddPathLine(path1, x + pw + r, y + pw, x + w - r - pw, y + pw)
Gdip_AddPathArc(path1, x + w - r2 - pw, y + pw, r2, r2, 270, 90)
Gdip_AddPathLine(path1, x + w - pw, y + r + pw, x + w - pw, y + h - r - pw)
Gdip_AddPathArc(path1, x + w - r2 - pw, y + h - r2 - pw, r2, r2, 0, 90)
Gdip_AddPathLine(path1, x + w - r - pw, y + h - pw, x + r + pw, y + h - pw)
Gdip_AddPathArc(path1, x + pw, y + h - r2 - pw, r2, r2, 90, 90)
Gdip_AddPathLine(path1, x + pw, y + h - r - pw, x + pw, y + r + pw)
Gdip_ClosePathFigure(path1)
If (Angle>0)
Gdip_RotatePathAtCenter(path1, Angle)
_E := Gdip_DrawPath(pGraphics, pPen, path1)
Gdip_DeletePath(path1)
return _E
}
Gdip_DrawEllipse(pGraphics, pPen, x, y, w, h) {
If (!pGraphics || !pPen || !w || !h)
Return 2
Return DllCall("gdiplus\GdipDrawEllipse", "UPtr", pGraphics, "UPtr", pPen, "float", x, "float", y, "float", w, "float", h)
}
Gdip_DrawBezier(pGraphics, pPen, x1, y1, x2, y2, x3, y3, x4, y4) {
If (!pGraphics || !pPen)
Return 2
Return DllCall("gdiplus\GdipDrawBezier"
, "UPtr", pGraphics, "UPtr", pPen
, "float", x1, "float", y1
, "float", x2, "float", y2
, "float", x3, "float", y3
, "float", x4, "float", y4)
}
Gdip_DrawBezierCurve(pGraphics, pPen, Points) {
If (!pGraphics || !pPen || !Points)
Return 2
iCount := CreatePointsF(PointsF, Points)
Return DllCall("gdiplus\GdipDrawBeziers", "UPtr", pGraphics, "UPtr", pPen, "UPtr", &PointsF, "UInt", iCount)
}
Gdip_DrawClosedCurve(pGraphics, pPen, Points, Tension:="") {
If (!pGraphics || !pPen || !Points)
Return 2
iCount := CreatePointsF(PointsF, Points)
If IsNumber(Tension)
Return DllCall("gdiplus\GdipDrawClosedCurve2", "UPtr", pGraphics, "UPtr", pPen, "UPtr", &PointsF, "UInt", iCount, "float", Tension)
Else
Return DllCall("gdiplus\GdipDrawClosedCurve", "UPtr", pGraphics, "UPtr", pPen, "UPtr", &PointsF, "UInt", iCount)
}
Gdip_DrawCurve(pGraphics, pPen, Points, Tension:="") {
If (!pGraphics || !pPen || !Points)
Return 2
iCount := CreatePointsF(PointsF, Points)
If IsNumber(Tension)
Return DllCall("gdiplus\GdipDrawCurve2", "UPtr", pGraphics, "UPtr", pPen, "UPtr", &PointsF, "UInt", iCount, "float", Tension)
Else
Return DllCall("gdiplus\GdipDrawCurve", "UPtr", pGraphics, "UPtr", pPen, "UPtr", &PointsF, "UInt", iCount)
}
Gdip_DrawPolygon(pGraphics, pPen, Points) {
If (!pGraphics || !pPen || !Points)
Return 2
iCount := CreatePointsF(PointsF, Points)
Return DllCall("gdiplus\GdipDrawPolygon", "UPtr", pGraphics, "UPtr", pPen, "UPtr", &PointsF, "UInt", iCount)
}
Gdip_DrawArc(pGraphics, pPen, x, y, w, h, StartAngle, SweepAngle) {
If (!pGraphics || !pPen || !w || !h)
Return 2
Return DllCall("gdiplus\GdipDrawArc"
, "UPtr", pGraphics
, "UPtr", pPen
, "float", x, "float", y
, "float", w, "float", h
, "float", StartAngle
, "float", SweepAngle)
}
Gdip_DrawPie(pGraphics, pPen, x, y, w, h, StartAngle, SweepAngle) {
If (!pGraphics || !pPen || !w || !h)
Return 2
Return DllCall("gdiplus\GdipDrawPie", "UPtr", pGraphics, "UPtr", pPen, "float", x, "float", y, "float", w, "float", h, "float", StartAngle, "float", SweepAngle)
}
Gdip_DrawLine(pGraphics, pPen, x1, y1, x2, y2) {
If (!pGraphics || !pPen)
Return 2
Return DllCall("gdiplus\GdipDrawLine"
, "UPtr", pGraphics
, "UPtr", pPen
, "float", x1, "float", y1
, "float", x2, "float", y2)
}
Gdip_DrawLines(pGraphics, pPen, Points) {
If (!pGraphics || !pPen || !Points)
Return 2
iCount := CreatePointsF(PointsF, Points)
Return DllCall("gdiplus\GdipDrawLines", "UPtr", pGraphics, "UPtr", pPen, "UPtr", &PointsF, "int", iCount)
}
Gdip_FillRectangle(pGraphics, pBrush, x, y, w, h) {
If (!pGraphics || !pBrush || !w || !h)
Return 2
Return DllCall("gdiplus\GdipFillRectangle"
, "UPtr", pGraphics
, "UPtr", pBrush
, "float", x, "float", y
, "float", w, "float", h)
}
Gdip_FillRoundedRectangle2(pGraphics, pBrush, x, y, w, h, r) {
r := (w <= h) ? (r < w // 2) ? r : w // 2 : (r < h // 2) ? r : h // 2
path1 := Gdip_CreatePath(0)
Gdip_AddPathRectangle(path1, x+r, y, w-(2*r), r)
Gdip_AddPathRectangle(path1, x+r, y+h-r, w-(2*r), r)
Gdip_AddPathRectangle(path1, x, y+r, r, h-(2*r))
Gdip_AddPathRectangle(path1, x+w-r, y+r, r, h-(2*r))
Gdip_AddPathRectangle(path1, x+r, y+r, w-(2*r), h-(2*r))
Gdip_AddPathPie(path1, x, y, 2*r, 2*r, 180, 90)
Gdip_AddPathPie(path1, x+w-(2*r), y, 2*r, 2*r, 270, 90)
Gdip_AddPathPie(path1, x, y+h-(2*r), 2*r, 2*r, 90, 90)
Gdip_AddPathPie(path1, x+w-(2*r), y+h-(2*r), 2*r, 2*r, 0, 90)
E := Gdip_FillPath(pGraphics, pBrush, path1)
Gdip_DeletePath(path1)
return E
}
Gdip_FillRoundedRectangle(pGraphics, pBrush, x, y, w, h, r) {
Region := Gdip_GetClipRegion(pGraphics)
Gdip_SetClipRect(pGraphics, x-r, y-r, 2*r, 2*r, 4)
Gdip_SetClipRect(pGraphics, x+w-r, y-r, 2*r, 2*r, 4)
Gdip_SetClipRect(pGraphics, x-r, y+h-r, 2*r, 2*r, 4)
Gdip_SetClipRect(pGraphics, x+w-r, y+h-r, 2*r, 2*r, 4)
_E := Gdip_FillRectangle(pGraphics, pBrush, x, y, w, h)
Gdip_SetClipRegion(pGraphics, Region, 0)
Gdip_SetClipRect(pGraphics, x-(2*r), y+r, w+(4*r), h-(2*r), 4)
Gdip_SetClipRect(pGraphics, x+r, y-(2*r), w-(2*r), h+(4*r), 4)
Gdip_FillEllipse(pGraphics, pBrush, x, y, 2*r, 2*r)
Gdip_FillEllipse(pGraphics, pBrush, x+w-(2*r), y, 2*r, 2*r)
Gdip_FillEllipse(pGraphics, pBrush, x, y+h-(2*r), 2*r, 2*r)
Gdip_FillEllipse(pGraphics, pBrush, x+w-(2*r), y+h-(2*r), 2*r, 2*r)
Gdip_SetClipRegion(pGraphics, Region, 0)
Gdip_DeleteRegion(Region)
return _E
}
Gdip_FillPolygon(pGraphics, pBrush, Points, FillMode:=0) {
If (!pGraphics || !pBrush || !Points)
Return 2
iCount := CreatePointsF(PointsF, Points)
Return DllCall("gdiplus\GdipFillPolygon", "UPtr", pGraphics, "UPtr", pBrush, "UPtr", &PointsF, "int", iCount, "int", FillMode)
}
Gdip_FillPie(pGraphics, pBrush, x, y, w, h, StartAngle, SweepAngle) {
If (!pGraphics || !pBrush || !w || !h)
Return 2
Return DllCall("gdiplus\GdipFillPie"
, "UPtr", pGraphics
, "UPtr", pBrush
, "float", x, "float", y
, "float", w, "float", h
, "float", StartAngle
, "float", SweepAngle)
}
Gdip_FillEllipse(pGraphics, pBrush, x, y, w, h) {
If (!pGraphics || !pBrush || !w || !h)
Return 2
Return DllCall("gdiplus\GdipFillEllipse", "UPtr", pGraphics, "UPtr", pBrush, "float", x, "float", y, "float", w, "float", h)
}
Gdip_FillRegion(pGraphics, pBrush, hRegion) {
If (!pGraphics || !pBrush || !hRegion)
Return 2
Return DllCall("gdiplus\GdipFillRegion", "UPtr", pGraphics, "UPtr", pBrush, "UPtr", hRegion)
}
Gdip_FillPath(pGraphics, pBrush, pPath) {
If (!pGraphics || !pBrush || !pPath)
Return 2
Return DllCall("gdiplus\GdipFillPath", "UPtr", pGraphics, "UPtr", pBrush, "UPtr", pPath)
}
Gdip_FillClosedCurve(pGraphics, pBrush, Points, Tension:="", FillMode:=0) {
If (!pGraphics || !pBrush || !Points)
Return 2
iCount := CreatePointsF(PointsF, Points)
If IsNumber(Tension)
Return DllCall("gdiplus\GdipFillClosedCurve2", "UPtr", pGraphics, "UPtr", pBrush, "UPtr", &PointsF, "int", iCount, "float", Tension, "int", FillMode)
Else
Return DllCall("gdiplus\GdipFillClosedCurve", "UPtr", pGraphics, "UPtr", pBrush, "UPtr", &PointsF, "int", iCount)
}
Gdip_DrawImagePointsRect(pGraphics, pBitmap, Points, sx:="", sy:="", sw:="", sh:="", Matrix:=1, Unit:=2, ImageAttr:=0) {
Static Ptr := "UPtr"
If !ImageAttr
{
if !IsNumber(Matrix)
ImageAttr := Gdip_SetImageAttributesColorMatrix(Matrix)
else if (Matrix != 1)
ImageAttr := Gdip_SetImageAttributesColorMatrix("1|0|0|0|0|0|1|0|0|0|0|0|1|0|0|0|0|0|" Matrix "|0|0|0|0|0|1")
} Else usrImageAttr := 1
if (sx="" && sy="" && sw="" && sh="")
{
sx := sy := 0
Gdip_GetImageDimensions(pBitmap, sw, sh)
}
iCount := CreatePointsF(PointsF, Points)
E := DllCall("gdiplus\GdipDrawImagePointsRect"
, Ptr, pGraphics
, Ptr, pBitmap
, Ptr, &PointsF
, "int", iCount
, "float", sX, "float", sY
, "float", sW, "float", sH
, "int", Unit
, Ptr, ImageAttr ? ImageAttr : 0
, Ptr, 0, Ptr, 0)
If (E=1 && A_LastError=8)
E := 3
if (ImageAttr && usrImageAttr!=1)
Gdip_DisposeImageAttributes(ImageAttr)
return E
}
Gdip_DrawImage(pGraphics, pBitmap, dx:="", dy:="", dw:="", dh:="", sx:="", sy:="", sw:="", sh:="", Matrix:=1, Unit:=2, ImageAttr:=0) {
If (!pGraphics || !pBitmap)
Return 2
If !ImageAttr
{
if !IsNumber(Matrix)
ImageAttr := Gdip_SetImageAttributesColorMatrix(Matrix)
else if (Matrix!=1)
ImageAttr := Gdip_SetImageAttributesColorMatrix("1|0|0|0|0|0|1|0|0|0|0|0|1|0|0|0|0|0|" Matrix "|0|0|0|0|0|1")
} Else usrImageAttr := 1
If (dx!="" && dy!="" && dw="" && dh="" && sx="" && sy="" && sw="" && sh="")
{
sx := sy := 0
sw := dw := Gdip_GetImageWidth(pBitmap)
sh := dh := Gdip_GetImageHeight(pBitmap)
} Else If (sx="" && sy="" && sw="" && sh="")
{
If (dx="" && dy="" && dw="" && dh="")
{
sx := dx := 0, sy := dy := 0
sw := dw := Gdip_GetImageWidth(pBitmap)
sh := dh := Gdip_GetImageHeight(pBitmap)
} Else
{
sx := sy := 0
Gdip_GetImageDimensions(pBitmap, sw, sh)
}
}
E := DllCall("gdiplus\GdipDrawImageRectRect"
, "UPtr", pGraphics
, "UPtr", pBitmap
, "float", dX, "float", dY
, "float", dW, "float", dH
, "float", sX, "float", sY
, "float", sW, "float", sH
, "int", Unit
, "UPtr", ImageAttr ? ImageAttr : 0
, "UPtr", 0, "UPtr", 0)
If (E=1 && A_LastError=8)
E := 3
if (ImageAttr && usrImageAttr!=1)
Gdip_DisposeImageAttributes(ImageAttr)
return E
}
Gdip_DrawImageFast(pGraphics, pBitmap, X:=0, Y:=0) {
return DllCall("gdiplus\GdipDrawImage"
, "UPtr", pGraphics
, "UPtr", pBitmap
, "float", X
, "float", Y)
}
Gdip_DrawImageRect(pGraphics, pBitmap, X, Y, W, H) {
return DllCall("gdiplus\GdipDrawImageRect"
, "UPtr", pGraphics
, "UPtr", pBitmap
, "float", X, "float", Y
, "float", W, "float", H)
}
Gdip_SetImageAttributesColorMatrix(clrMatrix, ImageAttr:=0, grayMatrix:=0, ColorAdjustType:=1, fEnable:=1, ColorMatrixFlag:=0) {
Static Ptr := "UPtr"
If (StrLen(clrMatrix)<5 && ImageAttr)
Return -1
If StrLen(clrMatrix)<5
Return
VarSetCapacity(ColourMatrix, 100, 0)
Matrix := RegExReplace(RegExReplace(clrMatrix, "^[^\d-\.]+([\d\.])", "$1", , 1), "[^\d-\.]+", "|")
Matrix := StrSplit(Matrix, "|")
Loop 25
{
M := (Matrix[A_Index] != "") ? Matrix[A_Index] : Mod(A_Index-1, 6) ? 0 : 1
NumPut(M, ColourMatrix, (A_Index-1)*4, "float")
}
Matrix := ""
Matrix := RegExReplace(RegExReplace(grayMatrix, "^[^\d-\.]+([\d\.])", "$1", , 1), "[^\d-\.]+", "|")
Matrix := StrSplit(Matrix, "|")
If (StrLen(Matrix)>2 && ColorMatrixFlag=2)
{
VarSetCapacity(GrayscaleMatrix, 100, 0)
Loop 25
{
M := (Matrix[A_Index] != "") ? Matrix[A_Index] : Mod(A_Index-1, 6) ? 0 : 1
NumPut(M, GrayscaleMatrix, (A_Index-1)*4, "float")
}
}
If !ImageAttr
{
created := 1
ImageAttr := Gdip_CreateImageAttributes()
}
E := DllCall("gdiplus\GdipSetImageAttributesColorMatrix"
, Ptr, ImageAttr
, "int", ColorAdjustType
, "int", fEnable
, Ptr, &ColourMatrix
, Ptr, &GrayscaleMatrix
, "int", ColorMatrixFlag)
E := created=1 ? ImageAttr : E
return E
}
Gdip_CreateImageAttributes() {
ImageAttr := 0
gdipLastError := DllCall("gdiplus\GdipCreateImageAttributes", "UPtr*", ImageAttr)
return ImageAttr
}
Gdip_CloneImageAttributes(ImageAttr) {
Static Ptr := "UPtr"
newImageAttr := 0
gdipLastError := DllCall("gdiplus\GdipCloneImageAttributes", Ptr, ImageAttr, "UPtr*", newImageAttr)
return newImageAttr
}
Gdip_SetImageAttributesThreshold(ImageAttr, Threshold, ColorAdjustType:=1, fEnable:=1) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetImageAttributesThreshold", Ptr, ImageAttr, "int", ColorAdjustType, "int", fEnable, "float", Threshold)
}
Gdip_SetImageAttributesResetMatrix(ImageAttr, ColorAdjustType) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetImageAttributesToIdentity", Ptr, ImageAttr, "int", ColorAdjustType)
}
Gdip_SetImageAttributesGamma(ImageAttr, Gamma, ColorAdjustType:=1, fEnable:=1) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetImageAttributesGamma", Ptr, ImageAttr, "int", ColorAdjustType, "int", fEnable, "float", Gamma)
}
Gdip_SetImageAttributesToggle(ImageAttr, ColorAdjustType, fEnable) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetImageAttributesNoOp", Ptr, ImageAttr, "int", ColorAdjustType, "int", fEnable)
}
Gdip_SetImageAttributesOutputChannel(ImageAttr, ColorChannelFlags, ColorAdjustType:=1, fEnable:=1) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetImageAttributesOutputChannel", Ptr, ImageAttr, "int", ColorAdjustType, "int", fEnable, "int", ColorChannelFlags)
}
Gdip_SetImageAttributesColorKeys(ImageAttr, ARGBLow, ARGBHigh, ColorAdjustType:=1, fEnable:=1) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetImageAttributesColorKeys", Ptr, ImageAttr, "int", ColorAdjustType, "int", fEnable, "uint", ARGBLow, "uint", ARGBHigh)
}
Gdip_SetImageAttributesWrapMode(ImageAttr, WrapMode, ARGB) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetImageAttributesWrapMode", Ptr, ImageAttr, "int", WrapMode, "uint", ARGB, "int", 0)
}
Gdip_ResetImageAttributes(ImageAttr, ColorAdjustType) {
Static Ptr := "UPtr"
DllCall("gdiplus\GdipResetImageAttributes", Ptr, ImageAttr, "int", ColorAdjustType)
}
Gdip_GraphicsFromImage(pBitmap, InterpolationMode:="", SmoothingMode:="", PageUnit:="", CompositingQuality:="") {
pGraphics := 0
gdipLastError := DllCall("gdiplus\GdipGetImageGraphicsContext", "UPtr", pBitmap, "UPtr*", pGraphics)
If (gdipLastError=1 && A_LastError=8)
gdipLastError := 3
If (pGraphics && !gdipLastError)
{
If (InterpolationMode!="")
Gdip_SetInterpolationMode(pGraphics, InterpolationMode)
If (SmoothingMode!="")
Gdip_SetSmoothingMode(pGraphics, SmoothingMode)
If (PageUnit!="")
Gdip_SetPageUnit(pGraphics, PageUnit)
If (CompositingQuality!="")
Gdip_SetCompositingQuality(pGraphics, CompositingQuality)
}
return pGraphics
}
Gdip_GraphicsFromHDC(hDC, hDevice:="", InterpolationMode:="", SmoothingMode:="", PageUnit:="", CompositingQuality:="") {
pGraphics := 0
If hDevice
gdipLastError := DllCall("Gdiplus\GdipCreateFromHDC2", "UPtr", hDC, "UPtr", hDevice, "UPtr*", pGraphics)
Else
gdipLastError := DllCall("gdiplus\GdipCreateFromHDC", "UPtr", hdc, "UPtr*", pGraphics)
If (gdipLastError=1 && A_LastError=8)
gdipLastError := 3
If (pGraphics && !gdipLastError)
{
If (InterpolationMode!="")
Gdip_SetInterpolationMode(pGraphics, InterpolationMode)
If (SmoothingMode!="")
Gdip_SetSmoothingMode(pGraphics, SmoothingMode)
If (PageUnit!="")
Gdip_SetPageUnit(pGraphics, PageUnit)
If (CompositingQuality!="")
Gdip_SetCompositingQuality(pGraphics, CompositingQuality)
}
return pGraphics
}
Gdip_GraphicsFromHWND(HWND, useICM:=0, InterpolationMode:="", SmoothingMode:="", PageUnit:="", CompositingQuality:="") {
pGraphics := 0
function2call := (useICM=1) ? "ICM" : ""
gdipLastError := DllCall("gdiplus\GdipCreateFromHWND" function2call, "UPtr", HWND, "UPtr*", pGraphics)
If (gdipLastError=1 && A_LastError=8)
gdipLastError := 3
If (pGraphics && !gdipLastError)
{
If (InterpolationMode!="")
Gdip_SetInterpolationMode(pGraphics, InterpolationMode)
If (SmoothingMode!="")
Gdip_SetSmoothingMode(pGraphics, SmoothingMode)
If (PageUnit!="")
Gdip_SetPageUnit(pGraphics, PageUnit)
If (CompositingQuality!="")
Gdip_SetCompositingQuality(pGraphics, CompositingQuality)
}
return pGraphics
}
Gdip_GetDC(pGraphics) {
hDC := 0
gdipLastError := DllCall("gdiplus\GdipGetDC", "UPtr", pGraphics, "UPtr*", hDC)
return hDC
}
Gdip_ReleaseDC(pGraphics, hdc) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipReleaseDC", Ptr, pGraphics, Ptr, hdc)
}
Gdip_GraphicsClear(pGraphics, ARGB:=0x00ffffff) {
If !pGraphics
return 2
return DllCall("gdiplus\GdipGraphicsClear", "UPtr", pGraphics, "int", ARGB)
}
Gdip_GraphicsFlush(pGraphics, intent) {
If !pGraphics
return 2
return DllCall("gdiplus\GdipFlush", "UPtr", pGraphics, "int", intent)
}
Gdip_BlurBitmap(pBitmap, BlurAmount, usePARGB:=0, quality:=7, softEdges:=1) {
If (!pBitmap || !IsNumber(BlurAmount))
Return
If (BlurAmount>100)
BlurAmount := 100
Else If (BlurAmount<1)
BlurAmount := 1
PixelFormat := (usePARGB=1) ? "0xE200B" : "0x26200A"
Gdip_GetImageDimensions(pBitmap, sWidth, sHeight)
dWidth := sWidth//BlurAmount
dHeight := sHeight//BlurAmount
pBitmap1 := Gdip_CreateBitmap(dWidth, dHeight, PixelFormat)
If !pBitmap1
Return
G1 := Gdip_GraphicsFromImage(pBitmap1, quality)
If !G1
{
Gdip_DisposeImage(pBitmap1, 1)
Return
}
E1 := Gdip_DrawImage(G1, pBitmap, 0, 0, dWidth, dHeight, 0, 0, sWidth, sHeight)
Gdip_DeleteGraphics(G1)
If E1
{
Gdip_DisposeImage(pBitmap1, 1)
Return
}
If (softEdges=1)
pBitmap2 := Gdip_CreateBitmap(sWidth, sHeight, PixelFormat)
Else
pBitmap2 := Gdip_CloneBitmapArea(pBitmap, 0, 0, sWidth, sHeight, PixelFormat, 0)
If !pBitmap2
{
Gdip_DisposeImage(pBitmap1, 1)
Return
}
G2 := Gdip_GraphicsFromImage(pBitmap2, quality)
If !G2
{
Gdip_DisposeImage(pBitmap1, 1)
Gdip_DisposeImage(pBitmap2, 1)
Return
}
E2 := Gdip_DrawImage(G2, pBitmap1, 0, 0, sWidth, sHeight, 0, 0, dWidth, dHeight)
Gdip_DeleteGraphics(G2)
Gdip_DisposeImage(pBitmap1)
If E2
{
Gdip_DisposeImage(pBitmap2, 1)
Return
}
return pBitmap2
}
Gdip_SaveBitmapToFile(pBitmap, sOutput, Quality:=75, toBase64orStream:=0) {
Static Ptr := "UPtr"
nCount := 0
nSize := 0
pStream := 0
hData := 0
_p := 0
SplitPath sOutput,,, Extension
If !RegExMatch(Extension, "^(?i:BMP|DIB|RLE|JPG|JPEG|JPE|JFIF|GIF|TIF|TIFF|PNG)$")
Return -1
Extension := "." Extension
DllCall("gdiplus\GdipGetImageEncodersSize", "uint*", nCount, "uint*", nSize)
VarSetCapacity(ci, nSize)
DllCall("gdiplus\GdipGetImageEncoders", "uint", nCount, "uint", nSize, Ptr, &ci)
If !(nCount && nSize)
Return -2
If (A_IsUnicode)
{
StrGet_Name := "StrGet"
N := (A_AhkVersion < 2) ? nCount : "nCount"
Loop %N%
{
sString := %StrGet_Name%(NumGet(ci, (idx := (48+7*A_PtrSize)*(A_Index-1))+32+3*A_PtrSize), "UTF-16")
If !InStr(sString, "*" Extension)
Continue
pCodec := &ci+idx
Break
}
} Else
{
N := (A_AhkVersion < 2) ? nCount : "nCount"
Loop %N%
{
Location := NumGet(ci, 76*(A_Index-1)+44)
nSize := DllCall("WideCharToMultiByte", "uint", 0, "uint", 0, "uint", Location, "int", -1, "uint", 0, "int",  0, "uint", 0, "uint", 0)
VarSetCapacity(sString, nSize)
DllCall("WideCharToMultiByte", "uint", 0, "uint", 0, "uint", Location, "int", -1, "str", sString, "int", nSize, "uint", 0, "uint", 0)
If !InStr(sString, "*" Extension)
Continue
pCodec := &ci+76*(A_Index-1)
Break
}
}
If !pCodec
Return -3
If (Quality!=75)
{
Quality := (Quality < 0) ? 0 : (Quality > 100) ? 100 : Quality
If (quality>95 && toBase64=1)
Quality := 95
If RegExMatch(Extension, "^\.(?i:JPG|JPEG|JPE|JFIF)$")
{
DllCall("gdiplus\GdipGetEncoderParameterListSize", Ptr, pBitmap, Ptr, pCodec, "uint*", nSize)
VarSetCapacity(EncoderParameters, nSize, 0)
DllCall("gdiplus\GdipGetEncoderParameterList", Ptr, pBitmap, Ptr, pCodec, "uint", nSize, Ptr, &EncoderParameters)
nCount := NumGet(EncoderParameters, "UInt")
N := (A_AhkVersion < 2) ? nCount : "nCount"
Loop %N%
{
elem := (24+A_PtrSize)*(A_Index-1) + 4 + (pad := A_PtrSize = 8 ? 4 : 0)
If (NumGet(EncoderParameters, elem+16, "UInt") = 1) && (NumGet(EncoderParameters, elem+20, "UInt") = 6)
{
_p := elem+&EncoderParameters-pad-4
NumPut(Quality, NumGet(NumPut(4, NumPut(1, _p+0)+20, "UInt")), "UInt")
Break
}
}
}
}
If (toBase64orStream=1 || toBase64orStream=2)
{
DllCall("ole32\CreateStreamOnHGlobal", "ptr",0, "int",true, "ptr*",pStream)
gdipLastError := DllCall("gdiplus\GdipSaveImageToStream", "ptr",pBitmap, "ptr",pStream, "ptr",pCodec, "uint", _p ? _p : 0)
If gdipLastError
Return -6
If (toBase64orStream=2)
Return pStream
DllCall("ole32\GetHGlobalFromStream", "ptr",pStream, "uint*",hData)
pData := DllCall("GlobalLock", "ptr",hData, "ptr")
nSize := DllCall("GlobalSize", "uint",pData)
VarSetCapacity(bin, nSize, 0)
DllCall("RtlMoveMemory", "ptr",&bin, "ptr",pData, "uptr",nSize)
DllCall("GlobalUnlock", "ptr",hData)
ObjRelease(pStream)
DllCall("GlobalFree", "ptr",hData)
DllCall("Crypt32.dll\CryptBinaryToStringA", "ptr",&bin, "uint",nSize, "uint",0x40000001, "ptr",0, "uint*",base64Length)
VarSetCapacity(base64, base64Length, 0)
_E := DllCall("Crypt32.dll\CryptBinaryToStringA", "ptr",&bin, "uint",nSize, "uint",0x40000001, "ptr",&base64, "uint*",base64Length)
If !_E
Return -7
VarSetCapacity(bin, 0)
Return StrGet(&base64, base64Length, "CP0")
}
_E := DllCall("gdiplus\GdipSaveImageToFile", Ptr, pBitmap, "WStr", sOutput, Ptr, pCodec, "uint", _p ? _p : 0)
gdipLastError := _E
Return _E ? -5 : 0
}
Gdip_SaveBitmapToStream(pBitmap, Format, Quality:=90) {
Format := "none." Format
Return Gdip_SaveBitmapToFile(pBitmap, Format, Quality, 2)
}
Gdip_GetPixel(pBitmap, x, y) {
ARGB := 0
gdipLastError := DllCall("gdiplus\GdipBitmapGetPixel", "UPtr", pBitmap, "int", x, "int", y, "uint*", ARGB)
Return ARGB
}
Gdip_GetPixelColor(pBitmap, x, y, Format) {
ARGBdec := Gdip_GetPixel(pBitmap, x, y)
If !ARGBdec
Return
If (format=1)
{
Return Format("{1:#x}", ARGBdec)
} Else If (format=2)
{
Gdip_FromARGB(ARGBdec, A, R, G, B)
Return R "," G "," B "," A
} Else If (format=3)
{
clr := Format("{1:#x}", ARGBdec)
Return "0x" SubStr(clr, -1) SubStr(clr, 7, 2) SubStr(clr, 5, 2)
} Else If (format=4)
{
Return SubStr(Format("{1:#x}", ARGBdec), 5)
} Else Return ARGBdec
}
Gdip_SetPixel(pBitmap, x, y, ARGB) {
return DllCall("gdiplus\GdipBitmapSetPixel", "UPtr", pBitmap, "int", x, "int", y, "int", ARGB)
}
Gdip_GetImageWidth(pBitmap) {
Width := 0
gdipLastError := DllCall("gdiplus\GdipGetImageWidth", "UPtr", pBitmap, "uint*", Width)
return Width
}
Gdip_GetImageHeight(pBitmap) {
Height := 0
gdipLastError := DllCall("gdiplus\GdipGetImageHeight", "UPtr", pBitmap, "uint*", Height)
return Height
}
Gdip_GetImageDimensions(pBitmap, ByRef Width, ByRef Height) {
Width := 0, Height := 0
If StrLen(pBitmap)<3
Return 2
E := Gdip_GetImageDimension(pBitmap, Width, Height)
Width := Round(Width)
Height := Round(Height)
return E
}
Gdip_GetImageDimension(pBitmap, ByRef w, ByRef h) {
Width := 0, Height := 0
If !pBitmap
Return 2
return DllCall("gdiplus\GdipGetImageDimension", "UPtr", pBitmap, "float*", w, "float*", h)
}
Gdip_GetImageBounds(pBitmap) {
If !pBitmap
Return 2
rData := {}
VarSetCapacity(RectF, 16, 0)
E := DllCall("gdiplus\GdipGetImageBounds", "UPtr", pBitmap, "UPtr", &RectF, "Int*", 0)
If (!E) {
rData.x := NumGet(&RectF, 0, "float")
, rData.y := NumGet(&RectF, 4, "float")
, rData.w := NumGet(&RectF, 8, "float")
, rData.h := NumGet(&RectF, 12, "float")
} Else {
Return E
}
return rData
}
Gdip_GetImageFlags(pBitmap) {
Flags := 0
gdipLastError := DllCall("gdiplus\GdipGetImageFlags", "UPtr", pBitmap, "UInt*", Flags)
Return Flags
}
Gdip_GetImageRawFormat(pBitmap) {
Static RawFormatsList := {"{B96B3CA9-0728-11D3-9D7B-0000F81EF32E}":"Undefined", "{B96B3CAA-0728-11D3-9D7B-0000F81EF32E}":"MemoryBMP", "{B96B3CAB-0728-11D3-9D7B-0000F81EF32E}":"BMP", "{B96B3CAC-0728-11D3-9D7B-0000F81EF32E}":"EMF", "{B96B3CAD-0728-11D3-9D7B-0000F81EF32E}":"WMF", "{B96B3CAE-0728-11D3-9D7B-0000F81EF32E}":"JPEG", "{B96B3CAF-0728-11D3-9D7B-0000F81EF32E}":"PNG", "{B96B3CB0-0728-11D3-9D7B-0000F81EF32E}":"GIF", "{B96B3CB1-0728-11D3-9D7B-0000F81EF32E}":"TIFF", "{B96B3CB2-0728-11D3-9D7B-0000F81EF32E}":"EXIF", "{B96B3CB5-0728-11D3-9D7B-0000F81EF32E}":"Icon"}
VarSetCapacity(pGuid, 16, 0)
E1 := DllCall("gdiplus\GdipGetImageRawFormat", "UPtr", pBitmap, "Ptr", &pGuid)
size := VarSetCapacity(sguid, (38 << !!A_IsUnicode) + 1, 0)
E2 := DllCall("ole32.dll\StringFromGUID2", "ptr", &pguid, "ptr", &sguid, "int", size)
R1 := E2 ? StrGet(&sguid) : E2
R2 := RawFormatsList[R1]
Return R2 ? R2 : R1
}
Gdip_GetImagePixelFormat(pBitmap, mode:=0) {
Static PixelFormatsList := {0x30101:"1-INDEXED", 0x30402:"4-INDEXED", 0x30803:"8-INDEXED", 0x101004:"16-GRAYSCALE", 0x021005:"16-RGB555", 0x21006:"16-RGB565", 0x61007:"16-ARGB1555", 0x21808:"24-RGB", 0x22009:"32-RGB", 0x26200A:"32-ARGB", 0xE200B:"32-PARGB", 0x10300C:"48-RGB", 0x34400D:"64-ARGB", 0x1A400E:"64-PARGB", 0x200f:"32-CMYK"}
PixelFormat := 0
gdipLastError := DllCall("gdiplus\GdipGetImagePixelFormat", "UPtr", pBitmap, "UPtr*", PixelFormat)
If gdipLastError
Return -1
If (mode=0)
Return PixelFormat
inHEX := Format("{1:#x}", PixelFormat)
If (PixelFormatsList.Haskey(inHEX) && mode=2)
result := PixelFormatsList[inHEX]
Else
result := inHEX
return result
}
Gdip_GetImageType(pBitmap) {
result := 0
gdipLastError := DllCall("gdiplus\GdipGetImageType", Ptr, pBitmap, "int*", result)
If gdipLastError
Return -1
Return result
}
Gdip_GetDPI(pGraphics, ByRef DpiX, ByRef DpiY) {
DpiX := Gdip_GetDpiX(pGraphics)
DpiY := Gdip_GetDpiY(pGraphics)
}
Gdip_GetDpiX(pGraphics) {
dpix := 0
gdipLastError := DllCall("gdiplus\GdipGetDpiX", "UPtr", pGraphics, "float*", dpix)
return Round(dpix)
}
Gdip_GetDpiY(pGraphics) {
dpiy := 0
gdipLastError := DllCall("gdiplus\GdipGetDpiY", "UPtr", pGraphics, "float*", dpiy)
return Round(dpiy)
}
Gdip_GetImageHorizontalResolution(pBitmap) {
dpix := 0
gdipLastError := DllCall("gdiplus\GdipGetImageHorizontalResolution", "UPtr", pBitmap, "float*", dpix)
return Round(dpix)
}
Gdip_GetImageVerticalResolution(pBitmap) {
dpiy := 0
gdipLastError := DllCall("gdiplus\GdipGetImageVerticalResolution", "UPtr", pBitmap, "float*", dpiy)
return Round(dpiy)
}
Gdip_BitmapSetResolution(pBitmap, dpix, dpiy) {
return DllCall("gdiplus\GdipBitmapSetResolution", "UPtr", pBitmap, "float", dpix, "float", dpiy)
}
Gdip_BitmapGetDPIResolution(pBitmap, ByRef dpix, ByRef dpiy) {
dpix := dpiy := 0
If StrLen(pBitmap)<3
Return 2
dpix := Gdip_GetImageHorizontalResolution(pBitmap)
dpiy := Gdip_GetImageVerticalResolution(pBitmap)
}
Gdip_CreateBitmapFromGraphics(pGraphics, Width, Height) {
pBitmap := 0
gdipLastError := DllCall("gdiplus\GdipCreateBitmapFromGraphics", "int", Width, "int", Height, "UPtr", pGraphics, "UPtr*", pBitmap)
Return pBitmap
}
Gdip_CreateBitmapFromFile(sFile, IconNumber:=1, IconSize:="", useICM:=0) {
Static Ptr := "UPtr"
PtrA := "UPtr*"
pBitmap := 0
pBitmapOld := 0
hIcon := 0
SplitPath sFile,,, Extension
if RegExMatch(Extension, "^(?i:exe|dll)$")
{
Sizes := IconSize ? IconSize : 256 "|" 128 "|" 64 "|" 48 "|" 32 "|" 16
BufSize := 16 + (2*A_PtrSize)
VarSetCapacity(buf, BufSize, 0)
For eachSize, Size in StrSplit( Sizes, "|" )
{
DllCall("PrivateExtractIcons", "str", sFile, "int", IconNumber-1, "int", Size, "int", Size, PtrA, hIcon, PtrA, 0, "uint", 1, "uint", 0)
if !hIcon
continue
if !DllCall("GetIconInfo", Ptr, hIcon, Ptr, &buf)
{
DestroyIcon(hIcon)
continue
}
hbmMask  := NumGet(buf, 12 + (A_PtrSize - 4))
hbmColor := NumGet(buf, 12 + (A_PtrSize - 4) + A_PtrSize)
if !(hbmColor && DllCall("GetObject", Ptr, hbmColor, "int", BufSize, Ptr, &buf))
{
DestroyIcon(hIcon)
continue
}
break
}
if !hIcon
return -1
Width := NumGet(buf, 4, "int"), Height := NumGet(buf, 8, "int")
hbm := CreateDIBSection(Width, -Height), hdc := CreateCompatibleDC(), obm := SelectObject(hdc, hbm)
if !DllCall("DrawIconEx", Ptr, hdc, "int", 0, "int", 0, Ptr, hIcon, "uint", Width, "uint", Height, "uint", 0, Ptr, 0, "uint", 3)
{
DestroyIcon(hIcon)
return -2
}
VarSetCapacity(dib, 104)
DllCall("GetObject", Ptr, hbm, "int", A_PtrSize = 8 ? 104 : 84, Ptr, &dib)
Stride := NumGet(dib, 12, "Int")
Bits := NumGet(dib, 20 + (A_PtrSize = 8 ? 4 : 0))
pBitmapOld := Gdip_CreateBitmap(Width, Height, 0, Stride, Bits)
pBitmap := Gdip_CreateBitmap(Width, Height)
_G := Gdip_GraphicsFromImage(pBitmap)
Gdip_DrawImage(_G, pBitmapOld, 0, 0, Width, Height, 0, 0, Width, Height)
SelectObject(hdc, obm), DeleteObject(hbm), DeleteDC(hdc)
Gdip_DeleteGraphics(_G), Gdip_DisposeImage(pBitmapOld)
DestroyIcon(hIcon)
} else
{
function2call := (useICM=1) ? "ICM" : ""
gdipLastError := DllCall("gdiplus\GdipCreateBitmapFromFile" function2call, "WStr", sFile, "UPtr*", pBitmap)
}
return pBitmap
}
Gdip_CreateBitmapFromFileSimplified(sFile, useICM:=0) {
function2call := (useICM=1) ? "ICM" : ""
gdipLastError := DllCall("gdiplus\GdipCreateBitmapFromFile" function2call, "WStr", sFile, "UPtr*", pBitmap)
return pBitmap
}
Gdip_CreateARGBBitmapFromHBITMAP(hImage) {
If !hImage
Return
E := DllCall("GetObject"
, "ptr", hImage
, "int", VarSetCapacity(dib, 76+2*(A_PtrSize=8?4:0)+2*A_PtrSize)
, "ptr", &dib)
If !E
Return
width  := NumGet(dib, 4, "uint")
height := NumGet(dib, 8, "uint")
bpp    := NumGet(dib, 18, "ushort")
if (bpp!=32)
return Gdip_CreateBitmapFromHBITMAP(hImage)
hdc := CreateCompatibleDC()
If !hdc
Return
obm := SelectObject(hdc, hImage)
cdc := CreateCompatibleDC(hdc)
If !cdc
{
SelectObject(hdc, obm), DeleteDC(hdc)
Return
}
hbm := CreateDIBSection(width, -height, hdc, 32, pBits)
If !hbm
{
DeleteDC(cdc), SelectObject(hdc, obm), DeleteDC(hdc)
Return
}
ob2 := SelectObject(cdc, hbm)
pBitmap := Gdip_CreateBitmap(width, height)
If !pBitmap
{
SelectObject(cdc, ob2)
DeleteObject(hbm), DeleteDC(cdc)
SelectObject(hdc, obm), DeleteDC(hdc)
Return
}
CreateRect(Rect, 0, 0, width, height)
VarSetCapacity(BitmapData, 16+2*A_PtrSize, 0)
, NumPut(       width, BitmapData,  0,  "uint")
, NumPut(      height, BitmapData,  4,  "uint")
, NumPut(   4 * width, BitmapData,  8,   "int")
, NumPut(     0xE200B, BitmapData, 12,   "int")
, NumPut(       pBits, BitmapData, 16,   "ptr")
E := DllCall("gdiplus\GdipBitmapLockBits"
,   "ptr", pBitmap
,   "ptr", &Rect
,  "uint", 6
,   "int", 0xE200B
,   "ptr", &BitmapData)
BitBlt(cdc, 0, 0, width, height, hdc, 0, 0)
If !E
DllCall("gdiplus\GdipBitmapUnlockBits", "ptr",pBitmap, "ptr",&BitmapData)
SelectObject(cdc, ob2)
DeleteObject(hbm), DeleteDC(cdc)
SelectObject(hdc, obm), DeleteDC(hdc)
return pBitmap
}
Gdip_CreateBitmapFromHBITMAP(hBitmap, hPalette:=0) {
pBitmap := 0
If !hBitmap
{
gdipLastError := 2
Return
}
gdipLastError := DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "UPtr", hBitmap, "UPtr", hPalette, "UPtr*", pBitmap)
return pBitmap
}
Gdip_CreateHBITMAPFromBitmap(pBitmap, Background:=0xffffffff) {
hBitmap := 0
If !pBitmap
{
gdipLastError := 2
Return
}
gdipLastError := DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "UPtr", pBitmap, "UPtr*", hBitmap, "int", Background)
return hBitmap
}
Gdip_CreateARGBHBITMAPFromBitmap(ByRef pBitmap) {
If !pBitmap
Return
hdc := CreateCompatibleDC()
If !hdc
Return
Gdip_GetImageDimensions(pBitmap, Width, Height)
hbm := CreateDIBSection(width, -height, hdc, 32, pBits)
If !hbm
{
DeleteObject(hdc)
Return
}
obm := SelectObject(hdc, hbm)
CreateRect(Rect, 0, 0, width, height)
VarSetCapacity(BitmapData, 16+2*A_PtrSize, 0)
, NumPut(     width, BitmapData,  0,   "uint")
, NumPut(    height, BitmapData,  4,   "uint")
, NumPut( 4 * width, BitmapData,  8,    "int")
, NumPut(   0xE200B, BitmapData, 12,    "int")
, NumPut(     pBits, BitmapData, 16,    "ptr")
E := DllCall("gdiplus\GdipBitmapLockBits"
,    "ptr", pBitmap
,    "ptr", &Rect
,   "uint", 5
,    "int", 0xE200B
,    "ptr", &BitmapData)
If !E
DllCall("gdiplus\GdipBitmapUnlockBits", "ptr", pBitmap, "ptr", &BitmapData)
SelectObject(hdc, obm)
DeleteObject(hdc)
return hbm
}
Gdip_CreateBitmapFromHICON(hIcon) {
pBitmap := 0
gdipLastError := DllCall("gdiplus\GdipCreateBitmapFromHICON", "UPtr", hIcon, "UPtr*", pBitmap)
return pBitmap
}
Gdip_CreateHICONFromBitmap(pBitmap) {
hIcon := 0
gdipLastError := DllCall("gdiplus\GdipCreateHICONFromBitmap", "UPtr", pBitmap, "UPtr*", hIcon)
return hIcon
}
Gdip_CreateBitmap(Width, Height, PixelFormat:=0, Stride:=0, Scan0:=0) {
If (!Width || !Height)
{
gdipLastError := 2
Return
}
pBitmap := 0
If !PixelFormat
PixelFormat := 0x26200A
gdipLastError := DllCall("gdiplus\GdipCreateBitmapFromScan0"
, "int", Width  , "int", Height
, "int", Stride , "int", PixelFormat
, "UPtr", Scan0 , "UPtr*", pBitmap)
Return pBitmap
}
Gdip_CreateBitmapFromClipboard() {
Static Ptr := "UPtr"
pid := DllCall("GetCurrentProcessId","uint")
hwnd := WinExist("ahk_pid " . pid)
if !DllCall("IsClipboardFormatAvailable", "uint", 8)
{
if DllCall("IsClipboardFormatAvailable", "uint", 2)
{
if !DllCall("OpenClipboard", Ptr, hwnd)
return -1
hData := DllCall("User32.dll\GetClipboardData", "UInt", 0x0002, "UPtr")
hBitmap := DllCall("User32.dll\CopyImage", "UPtr", hData, "UInt", 0, "Int", 0, "Int", 0, "UInt", 0x2004, "Ptr")
DllCall("CloseClipboard")
pBitmap := Gdip_CreateBitmapFromHBITMAP(hBitmap)
DeleteObject(hBitmap)
return pBitmap
}
return -2
}
if !DllCall("OpenClipboard", Ptr, hwnd)
return -1
hBitmap := DllCall("GetClipboardData", "uint", 2, Ptr)
if !hBitmap
{
DllCall("CloseClipboard")
return -3
}
DllCall("CloseClipboard")
If hBitmap
{
pBitmap := Gdip_CreateARGBBitmapFromHBITMAP(hBitmap)
If pBitmap
isUniform := Gdip_TestBitmapUniformity(pBitmap, 7, maxLevelIndex)
If (pBitmap && isUniform=1 && maxLevelIndex<=2)
{
Gdip_DisposeImage(pBitmap, 1)
pBitmap := Gdip_CreateBitmapFromHBITMAP(hBitmap)
}
DeleteObject(hBitmap)
}
if !pBitmap
return -4
return pBitmap
}
Gdip_SetBitmapToClipboard(pBitmap, hBitmap:=0) {
Static Ptr := "UPtr"
off1 := A_PtrSize = 8 ? 52 : 44
off2 := A_PtrSize = 8 ? 32 : 24
pid := DllCall("GetCurrentProcessId","uint")
hwnd := WinExist("ahk_pid " . pid)
r1 := DllCall("OpenClipboard", Ptr, hwnd)
If !r1
Return -1
If !hBitmap
{
If pBitmap
hBitmap := Gdip_CreateHBITMAPFromBitmap(pBitmap, 0)
}
If !hBitmap
{
DllCall("CloseClipboard")
Return -3
}
r2 := DllCall("EmptyClipboard")
If !r2
{
DeleteObject(hBitmap)
DllCall("CloseClipboard")
Return -2
}
DllCall("GetObject", Ptr, hBitmap, "int", VarSetCapacity(oi, A_PtrSize = 8 ? 104 : 84, 0), Ptr, &oi)
hdib := DllCall("GlobalAlloc", "uint", 2, Ptr, 40+NumGet(oi, off1, "UInt"), Ptr)
pdib := DllCall("GlobalLock", Ptr, hdib, Ptr)
DllCall("RtlMoveMemory", Ptr, pdib, Ptr, &oi+off2, Ptr, 40)
DllCall("RtlMoveMemory", Ptr, pdib+40, Ptr, NumGet(oi, off2 - A_PtrSize, Ptr), Ptr, NumGet(oi, off1, "UInt"))
DllCall("GlobalUnlock", Ptr, hdib)
DeleteObject(hBitmap)
r3 := DllCall("SetClipboardData", "uint", 8, Ptr, hdib)
DllCall("CloseClipboard")
DllCall("GlobalFree", Ptr, hdib)
E := r3 ? 0 : -4
Return E
}
Gdip_CloneBitmapArea(pBitmap, x:="", y:="", w:=0, h:=0, PixelFormat:=0, KeepPixelFormat:=0) {
If !pBitmap
{
gdipLastError := 2
Return
}
pBitmapDest := 0
If !PixelFormat
PixelFormat := 0x26200A
If (KeepPixelFormat=1)
PixelFormat := Gdip_GetImagePixelFormat(pBitmap, 1)
If (y="")
y := 0
If (x="")
x := 0
If (!w || !h)
Gdip_GetImageDimensions(pBitmap, w, h)
gdipLastError := DllCall("gdiplus\GdipCloneBitmapArea"
, "float", x, "float", y
, "float", w, "float", h
, "int", PixelFormat
, "UPtr", pBitmap
, "UPtr*", pBitmapDest)
return pBitmapDest
}
Gdip_CloneBitmap(pBitmap) {
If !pBitmap
{
gdipLastError := 2
Return
}
pBitmapDest := 0
gdipLastError := DllCall("gdiplus\GdipCloneImage"
, "UPtr", pBitmap, "UPtr*", pBitmapDest)
return pBitmapDest
}
Gdip_BitmapSelectActiveFrame(pBitmap, FrameIndex) {
Countu := 0
CountFrames := 0
Static Ptr := "UPtr"
DllCall("gdiplus\GdipImageGetFrameDimensionsCount", Ptr, pBitmap, "UInt*", Countu)
VarSetCapacity(dIDs, 16, 0)
DllCall("gdiplus\GdipImageGetFrameDimensionsList", Ptr, pBitmap, "Uint", &dIDs, "UInt", Countu)
DllCall("gdiplus\GdipImageGetFrameCount", Ptr, pBitmap, "Uint", &dIDs, "UInt*", CountFrames)
If (FrameIndex>CountFrames)
FrameIndex := CountFrames
Else If (FrameIndex<1)
FrameIndex := 0
E := DllCall("gdiplus\GdipImageSelectActiveFrame", Ptr, pBitmap, Ptr, &dIDs, "uint", FrameIndex)
If E
Return -1
Return CountFrames
}
Gdip_GetBitmapFramesCount(pBitmap) {
Countu := 0
CountFrames := 0
Static Ptr := "UPtr"
DllCall("gdiplus\GdipImageGetFrameDimensionsCount", Ptr, pBitmap, "UInt*", Countu)
VarSetCapacity(dIDs, 16, 0)
DllCall("gdiplus\GdipImageGetFrameDimensionsList", Ptr, pBitmap, "Uint", &dIDs, "UInt", Countu)
DllCall("gdiplus\GdipImageGetFrameCount", Ptr, pBitmap, "Uint", &dIDs, "UInt*", CountFrames)
Return CountFrames
}
Gdip_CreateCachedBitmap(pBitmap, pGraphics) {
pCachedBitmap := 0
Static Ptr := "UPtr"
gdipLastError := := DllCall("gdiplus\GdipCreateCachedBitmap", Ptr, pBitmap, Ptr, pGraphics, "Ptr*", pCachedBitmap)
return pCachedBitmap
}
Gdip_DeleteCachedBitmap(pCachedBitmap) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipDeleteCachedBitmap", Ptr, pCachedBitmap)
}
Gdip_DrawCachedBitmap(pGraphics, pCachedBitmap, X, Y) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipDrawCachedBitmap", Ptr, pGraphics, Ptr, pCachedBitmap, "int", X, "int", Y)
}
Gdip_ImageRotateFlip(pBitmap, RotateFlipType:=1) {
return DllCall("gdiplus\GdipImageRotateFlip", "UPtr", pBitmap, "int", RotateFlipType)
}
Gdip_RotateBitmapAtCenter(pBitmap, Angle, pBrush:=0, InterpolationMode:=7, PixelFormat:=0) {
If !pBitmap
Return
If !Angle
{
newBitmap := Gdip_CloneBitmap(pBitmap)
Return newBitmap
}
Gdip_GetImageDimensions(pBitmap, Width, Height)
Gdip_GetRotatedDimensions(Width, Height, Angle, RWidth, RHeight)
Gdip_GetRotatedTranslation(Width, Height, Angle, xTranslation, yTranslation)
If (RWidth*RHeight>536848912) || (Rwidth>32100) || (RHeight>32100)
Return
PixelFormatReadable := Gdip_GetImagePixelFormat(pBitmap, 2)
If InStr(PixelFormatReadable, "indexed")
{
hbm := CreateDIBSection(RWidth, RHeight,,24)
If !hbm
Return
hDC := CreateCompatibleDC()
If !hDC
{
DeleteDC(hDC)
Return
}
obm := SelectObject(hDC, hbm)
G := Gdip_GraphicsFromHDC(hDC, InterpolationMode, 4)
indexedMode := 1
} Else
{
If (PixelFormat=-1)
PixelFormat := "0xE200B"
newBitmap := Gdip_CreateBitmap(RWidth, RHeight, PixelFormat)
If StrLen(newBitmap)>1
G := Gdip_GraphicsFromImage(newBitmap, InterpolationMode, 4)
}
If (!newBitmap || !G)
{
Gdip_DisposeImage(newBitmap, 1)
Gdip_DeleteGraphics(G)
SelectObject(hDC, obm)
DeleteObject(hbm)
DeleteDC(hDC)
Return
}
If (pBrush=0)
{
pBrush := Gdip_BrushCreateSolid("0xFF000000")
defaultBrush := 1
}
If StrLen(pBrush)>1
Gdip_FillRectangle(G, pBrush, 0, 0, RWidth, RHeight)
Gdip_TranslateWorldTransform(G, xTranslation, yTranslation)
Gdip_RotateWorldTransform(G, Angle)
r := Gdip_DrawImage(G, pBitmap, 0, 0, Width, Height)
If (indexedMode=1)
{
newBitmap := !r ? Gdip_CreateBitmapFromHBITMAP(hbm) : ""
SelectObject(hDC, obm)
DeleteObject(hbm)
DeleteDC(hDC)
} Else If r
{
Gdip_DisposeImage(newBitmap, 1)
newBitmap := ""
}
Gdip_DeleteGraphics(G)
If (defaultBrush=1)
Gdip_DeleteBrush(pBrush)
Return newBitmap
}
Gdip_ResizeBitmap(pBitmap, givenW, givenH, KeepRatio, InterpolationMode:="", KeepPixelFormat:=0, checkTooLarge:=0) {
If (!pBitmap || !givenW || !givenH)
Return
Gdip_GetImageDimensions(pBitmap, Width, Height)
If (KeepRatio=1)
{
calcIMGdimensions(Width, Height, givenW, givenH, ResizedW, ResizedH)
} Else
{
ResizedW := givenW
ResizedH := givenH
}
If (((ResizedW*ResizedH>536848912) || (ResizedW>32100) || (ResizedH>32100)) && checkTooLarge=1)
Return
PixelFormatReadable := Gdip_GetImagePixelFormat(pBitmap, 2)
If (KeepPixelFormat=1)
PixelFormat := Gdip_GetImagePixelFormat(pBitmap, 1)
Else If (KeepPixelFormat=-1)
PixelFormat := "0xE200B"
Else If Strlen(KeepPixelFormat)>3
PixelFormat := KeepPixelFormat
If InStr(PixelFormatReadable, "indexed")
{
hbm := CreateDIBSection(ResizedW, ResizedH,,24)
If !hbm
Return
hDC := CreateCompatibleDC()
If !hDC
{
DeleteDC(hdc)
Return
}
obm := SelectObject(hDC, hbm)
G := Gdip_GraphicsFromHDC(hDC, InterpolationMode, 4)
Gdip_SetPixelOffsetMode(G, 2)
If G
r := Gdip_DrawImage(G, pBitmap, 0, 0, ResizedW, ResizedH)
newBitmap := !r ? Gdip_CreateBitmapFromHBITMAP(hbm) : ""
If (KeepPixelFormat=1 && newBitmap)
Gdip_BitmapSetColorDepth(newBitmap, SubStr(PixelFormatReadable, 1, 1), 1)
SelectObject(hdc, obm)
DeleteObject(hbm)
DeleteDC(hdc)
Gdip_DeleteGraphics(G)
} Else
{
newBitmap := Gdip_CreateBitmap(ResizedW, ResizedH, PixelFormat)
If StrLen(newBitmap)>2
{
G := Gdip_GraphicsFromImage(newBitmap, InterpolationMode, 4)
Gdip_SetPixelOffsetMode(G, 2)
If G
r := Gdip_DrawImage(G, pBitmap, 0, 0, ResizedW, ResizedH)
Gdip_DeleteGraphics(G)
If (r || !G)
{
Gdip_DisposeImage(newBitmap, 1)
newBitmap := ""
}
}
}
Return newBitmap
}
Gdip_CreatePen(ARGB, w, Unit:=2) {
pPen := 0
gdipLastError := DllCall("gdiplus\GdipCreatePen1", "UInt", ARGB, "float", w, "int", Unit, "UPtr*", pPen)
return pPen
}
Gdip_CreatePenFromBrush(pBrush, w, Unit:=2) {
pPen := 0
gdipLastError := DllCall("gdiplus\GdipCreatePen2", "UPtr", pBrush, "float", w, "int", 2, "UPtr*", pPen, "int", Unit)
return pPen
}
Gdip_SetPenWidth(pPen, width) {
return DllCall("gdiplus\GdipSetPenWidth", "UPtr", pPen, "float", width)
}
Gdip_GetPenWidth(pPen) {
width := 0
gdipLastError := DllCall("gdiplus\GdipGetPenWidth", "UPtr", pPen, "float*", width)
If gdipLastError
return -1
return width
}
Gdip_GetPenDashStyle(pPen) {
DashStyle := 0
gdipLastError := DllCall("gdiplus\GdipGetPenDashStyle", "UPtr", pPen, "float*", DashStyle)
If gdipLastError
return -1
return DashStyle
}
Gdip_SetPenColor(pPen, ARGB) {
return DllCall("gdiplus\GdipSetPenColor", "UPtr", pPen, "UInt", ARGB)
}
Gdip_GetPenColor(pPen) {
ARGB := 0
gdipLastError := DllCall("gdiplus\GdipGetPenColor", "UPtr", pPen, "UInt*", ARGB)
If gdipLastError
return -1
return Format("{1:#x}", ARGB)
}
Gdip_SetPenBrushFill(pPen, pBrush) {
return DllCall("gdiplus\GdipSetPenBrushFill", "UPtr", pPen, "UPtr", pBrush)
}
Gdip_ResetPenTransform(pPen) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipResetPenTransform", Ptr, pPen)
}
Gdip_MultiplyPenTransform(pPen, hMatrix, matrixOrder:=0) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipMultiplyPenTransform", Ptr, pPen, Ptr, hMatrix, "int", matrixOrder)
}
Gdip_RotatePenTransform(pPen, Angle, matrixOrder:=0) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipRotatePenTransform", Ptr, pPen, "float", Angle, "int", matrixOrder)
}
Gdip_ScalePenTransform(pPen, ScaleX, ScaleY, matrixOrder:=0) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipScalePenTransform", Ptr, pPen, "float", ScaleX, "float", ScaleY, "int", matrixOrder)
}
Gdip_TranslatePenTransform(pPen, X, Y, matrixOrder:=0) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipTranslatePenTransform", Ptr, pPen, "float", X, "float", Y, "int", matrixOrder)
}
Gdip_SetPenTransform(pPen, pMatrix) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetPenTransform", Ptr, pPen, Ptr, pMatrix)
}
Gdip_GetPenTransform(pPen) {
Static Ptr := "UPtr"
pMatrix := 0
DllCall("gdiplus\GdipGetPenTransform", Ptr, pPen, "UPtr*", pMatrix)
Return pMatrix
}
Gdip_GetPenBrushFill(pPen) {
Static Ptr := "UPtr"
pBrush := 0
E := DllCall("gdiplus\GdipGetPenBrushFill", Ptr, pPen, "int*", pBrush)
Return pBrush
}
Gdip_GetPenFillType(pPen) {
Static Ptr := "UPtr"
result := 0
gdipLastError := DllCall("gdiplus\GdipGetPenFillType", Ptr, pPen, "int*", result)
If gdipLastError
return -2
Return result
}
Gdip_GetPenStartCap(pPen) {
result := 0
Static Ptr := "UPtr"
gdipLastError := DllCall("gdiplus\GdipGetPenStartCap", Ptr, pPen, "int*", result)
If gdipLastError
return -1
Return result
}
Gdip_GetPenEndCap(pPen) {
result := 0
Static Ptr := "UPtr"
gdipLastError := DllCall("gdiplus\GdipGetPenEndCap", Ptr, pPen, "int*", result)
If gdipLastError
return -1
Return result
}
Gdip_GetPenDashCaps(pPen) {
result := 0
Static Ptr := "UPtr"
gdipLastError := DllCall("gdiplus\GdipGetPenDashCap197819", Ptr, pPen, "int*", result)
If gdipLastError
return -1
Return result
}
Gdip_GetPenAlignment(pPen) {
result := 0
Static Ptr := "UPtr"
gdipLastError := DllCall("gdiplus\GdipGetPenMode", Ptr, pPen, "int*", result)
If gdipLastError
return -1
Return result
}
Gdip_SetPenLineCaps(pPen, StartCap, EndCap, DashCap) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetPenLineCap197819", Ptr, pPen, "int", StartCap, "int", EndCap, "int", DashCap)
}
Gdip_SetPenStartCap(pPen, LineCap) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetPenStartCap", Ptr, pPen, "int", LineCap)
}
Gdip_SetPenEndCap(pPen, LineCap) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetPenEndCap", Ptr, pPen, "int", LineCap)
}
Gdip_SetPenDashCaps(pPen, LineCap) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetPenDashCap197819", Ptr, pPen, "int", LineCap)
}
Gdip_SetPenAlignment(pPen, Alignment) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetPenMode", Ptr, pPen, "int", Alignment)
}
Gdip_GetPenCompoundCount(pPen) {
result := 0
E := DllCall("gdiplus\GdipGetPenCompoundCount", Ptr, pPen, "int*", result)
If E
Return -1
Return result
}
Gdip_SetPenCompoundArray(pPen, inCompounds) {
arrCompounds := StrSplit(inCompounds, "|")
totalCompounds := arrCompounds.Length()
VarSetCapacity(pCompounds, 8 * totalCompounds, 0)
Loop %totalCompounds%
NumPut(arrCompounds[A_Index], &pCompounds, 4*(A_Index - 1), "float")
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetPenCompoundArray", Ptr, pPen, Ptr, &pCompounds, "int", totalCompounds)
}
Gdip_SetPenDashStyle(pPen, DashStyle) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetPenDashStyle", Ptr, pPen, "Int", DashStyle)
}
Gdip_SetPenDashArray(pPen, Dashes) {
Static Ptr := "UPtr"
Points := StrSplit(Dashes, ",")
PointsCount := Points.Length()
VarSetCapacity(PointsF, 8 * PointsCount, 0)
Loop %PointsCount%
NumPut(Points[A_Index], &PointsF, 4*(A_Index - 1), "float")
Return DllCall("gdiplus\GdipSetPenDashArray", Ptr, pPen, Ptr, &PointsF, "int", PointsCount)
}
Gdip_SetPenDashOffset(pPen, Offset) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetPenDashOffset", Ptr, pPen, "float", Offset)
}
Gdip_GetPenDashArray(pPen) {
iCount := Gdip_GetPenDashCount(pPen)
If (iCount=-1)
Return 0
VarSetCapacity(PointsF, 8 * iCount, 0)
Static Ptr := "UPtr"
DllCall("gdiplus\GdipGetPenDashArray", Ptr, pPen, "uPtr", &PointsF, "int", iCount)
Loop %iCount%
{
A := NumGet(&PointsF, 4*(A_Index-1), "float")
printList .= A ","
}
Return Trim(printList, ",")
}
Gdip_GetPenCompoundArray(pPen) {
iCount := Gdip_GetPenCompoundCount(pPen)
VarSetCapacity(PointsF, 4 * iCount, 0)
Static Ptr := "UPtr"
DllCall("gdiplus\GdipGetPenCompoundArray", Ptr, pPen, "uPtr", &PointsF, "int", iCount)
Loop %iCount%
{
A := NumGet(&PointsF, 4*(A_Index-1), "float")
printList .= A "|"
}
Return Trim(printList, "|")
}
Gdip_SetPenLineJoin(pPen, LineJoin) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetPenLineJoin", Ptr, pPen, "int", LineJoin)
}
Gdip_SetPenMiterLimit(pPen, MiterLimit) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetPenMiterLimit", Ptr, pPen, "float", MiterLimit)
}
Gdip_SetPenUnit(pPen, Unit) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetPenUnit", Ptr, pPen, "int", Unit)
}
Gdip_GetPenDashCount(pPen) {
result := 0
E := DllCall("gdiplus\GdipGetPenDashCount", Ptr, pPen, "int*", result)
If E
Return -1
Return result
}
Gdip_GetPenDashOffset(pPen) {
result := 0
E := DllCall("gdiplus\GdipGetPenDashOffset", Ptr, pPen, "float*", result)
If E
Return -1
Return result
}
Gdip_GetPenLineJoin(pPen) {
result := 0
E := DllCall("gdiplus\GdipGetPenLineJoin", Ptr, pPen, "int*", result)
If E
Return -1
Return result
}
Gdip_GetPenMiterLimit(pPen) {
result := 0
E := DllCall("gdiplus\GdipGetPenMiterLimit", Ptr, pPen, "float*", result)
If E
Return -1
Return result
}
Gdip_GetPenUnit(pPen) {
result := 0
E := DllCall("gdiplus\GdipGetPenUnit", Ptr, pPen, "int*", result)
If E
Return -1
Return result
}
Gdip_ClonePen(pPen) {
newPen := 0
gdipLastError := DllCall("gdiplus\GdipClonePen", "UPtr", pPen, "UPtr*", newPen)
Return newPen
}
Gdip_BrushCreateSolid(ARGB:=0xff000000) {
pBrush := 0
E := DllCall("gdiplus\GdipCreateSolidFill", "UInt", ARGB, "UPtr*", pBrush)
return pBrush
}
Gdip_SetSolidFillColor(pBrush, ARGB) {
return DllCall("gdiplus\GdipSetSolidFillColor", "UPtr", pBrush, "UInt", ARGB)
}
Gdip_GetSolidFillColor(pBrush) {
ARGB := 0
E := DllCall("gdiplus\GdipGetSolidFillColor", "UPtr", pBrush, "UInt*", ARGB)
If E
return -1
return Format("{1:#x}", ARGB)
}
Gdip_BrushCreateHatch(ARGBfront, ARGBback, HatchStyle:=0) {
pBrush := 0
gdipLastError := DllCall("gdiplus\GdipCreateHatchBrush", "int", HatchStyle, "UInt", ARGBfront, "UInt", ARGBback, "UPtr*", pBrush)
return pBrush
}
Gdip_GetHatchBackgroundColor(pHatchBrush) {
ARGB := 0
Static Ptr := "UPtr"
E := DllCall("gdiplus\GdipGetHatchBackgroundColor", Ptr, pHatchBrush, "uint*", ARGB)
If E
Return -1
return Format("{1:#x}", ARGB)
}
Gdip_GetHatchForegroundColor(pHatchBrush) {
ARGB := 0
Static Ptr := "UPtr"
E := DllCall("gdiplus\GdipGetHatchForegroundColor", Ptr, pHatchBrush, "uint*", ARGB)
If E
Return -1
return Format("{1:#x}", ARGB)
}
Gdip_GetHatchStyle(pHatchBrush) {
result := 0
Static Ptr := "UPtr"
E := DllCall("gdiplus\GdipGetHatchStyle", Ptr, pHatchBrush, "int*", result)
If E
Return -1
Return result
}
Gdip_CreateTextureBrush(pBitmap, WrapMode:=1, x:=0, y:=0, w:="", h:="", matrix:="", ScaleX:="", ScaleY:="", Angle:=0, ImageAttr:=0) {
Static Ptr := "UPtr"
PtrA := "UPtr*"
pBrush := 0
if !(w && h)
{
gdipLastError := DllCall("gdiplus\GdipCreateTexture", Ptr, pBitmap, "int", WrapMode, PtrA, pBrush)
} else
{
If !ImageAttr
{
if !IsNumber(Matrix)
ImageAttr := Gdip_SetImageAttributesColorMatrix(Matrix)
else if (Matrix != 1)
ImageAttr := Gdip_SetImageAttributesColorMatrix("1|0|0|0|0|0|1|0|0|0|0|0|1|0|0|0|0|0|" Matrix "|0|0|0|0|0|1")
} Else usrImageAttr := 1
If ImageAttr
{
gdipLastError := DllCall("gdiplus\GdipCreateTextureIA", Ptr, pBitmap, Ptr, ImageAttr, "float", x, "float", y, "float", w, "float", h, PtrA, pBrush)
If pBrush
Gdip_SetTextureWrapMode(pBrush, WrapMode)
} Else
gdipLastError := DllCall("gdiplus\GdipCreateTexture2", Ptr, pBitmap, "int", WrapMode, "float", x, "float", y, "float", w, "float", h, PtrA, pBrush)
}
if (ImageAttr && usrImageAttr!=1)
Gdip_DisposeImageAttributes(ImageAttr)
If (ScaleX && ScaleX && pBrush)
Gdip_ScaleTextureTransform(pBrush, ScaleX, ScaleY)
If (Angle && pBrush)
Gdip_RotateTextureTransform(pBrush, Angle)
return pBrush
}
Gdip_RotateTextureTransform(pTexBrush, Angle, MatrixOrder:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipRotateTextureTransform", Ptr, pTexBrush, "float", Angle, "int", MatrixOrder)
}
Gdip_ScaleTextureTransform(pTexBrush, ScaleX, ScaleY, MatrixOrder:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipScaleTextureTransform", Ptr, pTexBrush, "float", ScaleX, "float", ScaleY, "int", MatrixOrder)
}
Gdip_TranslateTextureTransform(pTexBrush, X, Y, MatrixOrder:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipTranslateTextureTransform", Ptr, pTexBrush, "float", X, "float", Y, "int", MatrixOrder)
}
Gdip_MultiplyTextureTransform(pTexBrush, hMatrix, matrixOrder:=0) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipMultiplyTextureTransform", Ptr, pTexBrush, Ptr, hMatrix, "int", matrixOrder)
}
Gdip_SetTextureTransform(pTexBrush, hMatrix) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetTextureTransform", Ptr, pTexBrush, Ptr, hMatrix)
}
Gdip_GetTextureTransform(pTexBrush) {
hMatrix := 0
Static Ptr := "UPtr"
gdipLastError := DllCall("gdiplus\GdipGetTextureTransform", Ptr, pTexBrush, "UPtr*", hMatrix)
Return hMatrix
}
Gdip_ResetTextureTransform(pTexBrush) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipResetTextureTransform", Ptr, pTexBrush)
}
Gdip_SetTextureWrapMode(pTexBrush, WrapMode) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetTextureWrapMode", Ptr, pTexBrush, "int", WrapMode)
}
Gdip_GetTextureWrapMode(pTexBrush) {
result := 0
Static Ptr := "UPtr"
E := DllCall("gdiplus\GdipGetTextureWrapMode", Ptr, pTexBrush, "int*", result)
If E
return -1
Return result
}
Gdip_GetTextureImage(pTexBrush) {
Static Ptr := "UPtr"
pBitmapDest := 0
gdipLastError := DllCall("gdiplus\GdipGetTextureImage", Ptr, pTexBrush
, "UPtr*", pBitmapDest)
Return pBitmapDest
}
Gdip_CreateLineBrush(x1, y1, x2, y2, ARGB1, ARGB2, WrapMode:=1) {
return Gdip_CreateLinearGrBrush(x1, y1, x2, y2, ARGB1, ARGB2, WrapMode)
}
Gdip_CreateLinearGrBrush(x1, y1, x2, y2, ARGB1, ARGB2, WrapMode:=1) {
Static Ptr := "UPtr"
CreatePointF(PointF1, x1, y1)
CreatePointF(PointF2, x2, y2)
pLinearGradientBrush := 0
gdipLastError := DllCall("gdiplus\GdipCreateLineBrush", Ptr, &PointF1, Ptr, &PointF2, "Uint", ARGB1, "Uint", ARGB2, "int", WrapMode, "UPtr*", pLinearGradientBrush)
return pLinearGradientBrush
}
Gdip_SetLinearGrBrushColors(pLinearGradientBrush, ARGB1, ARGB2) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetLineColors", Ptr, pLinearGradientBrush, "UInt", ARGB1, "UInt", ARGB2)
}
Gdip_GetLinearGrBrushColors(pLinearGradientBrush, ByRef ARGB1, ByRef ARGB2) {
Static Ptr := "UPtr"
VarSetCapacity(colors, 8, 0)
E := DllCall("gdiplus\GdipGetLineColors", Ptr, pLinearGradientBrush, "Ptr", &colors)
ARGB1 := NumGet(colors, 0, "UInt")
ARGB2 := NumGet(colors, 4, "UInt")
ARGB1 := Format("{1:#x}", ARGB1)
ARGB2 := Format("{1:#x}", ARGB2)
return E
}
Gdip_CreateLineBrushFromRect(x, y, w, h, ARGB1, ARGB2, LinearGradientMode:=1, WrapMode:=1) {
return Gdip_CreateLinearGrBrushFromRect(x, y, w, h, ARGB1, ARGB2, LinearGradientMode, WrapMode)
}
Gdip_CreateLinearGrBrushFromRect(x, y, w, h, ARGB1, ARGB2, LinearGradientMode:=1, WrapMode:=1) {
CreateRectF(RectF, x, y, w, h)
pLinearGradientBrush := 0
gdipLastError := DllCall("gdiplus\GdipCreateLineBrushFromRect", "UPtr", &RectF, "int", ARGB1, "int", ARGB2, "int", LinearGradientMode, "int", WrapMode, "UPtr*", pLinearGradientBrush)
return pLinearGradientBrush
}
Gdip_GetLinearGrBrushGammaCorrection(pLinearGradientBrush) {
result := 0
gdipLastError := DllCall("gdiplus\GdipGetLineGammaCorrection", "UPtr", pLinearGradientBrush, "int*", result)
If gdipLastError
Return -1
Return result
}
Gdip_SetLinearGrBrushGammaCorrection(pLinearGradientBrush, UseGammaCorrection) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetLineGammaCorrection", Ptr, pLinearGradientBrush, "int", UseGammaCorrection)
}
Gdip_GetLinearGrBrushRect(pLinearGradientBrush) {
rData := {}
VarSetCapacity(RectF, 16, 0)
E := DllCall("gdiplus\GdipGetLineRect", "UPtr", pLinearGradientBrush, "UPtr", &RectF)
If (!E) {
rData.x := NumGet(&RectF, 0, "float")
, rData.y := NumGet(&RectF, 4, "float")
, rData.w := NumGet(&RectF, 8, "float")
, rData.h := NumGet(&RectF, 12, "float")
} Else {
Return E
}
return rData
}
Gdip_ResetLinearGrBrushTransform(pLinearGradientBrush) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipResetLineTransform", Ptr, pLinearGradientBrush)
}
Gdip_ScaleLinearGrBrushTransform(pLinearGradientBrush, ScaleX, ScaleY, matrixOrder:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipScaleLineTransform", Ptr, pLinearGradientBrush, "float", ScaleX, "float", ScaleY, "int", matrixOrder)
}
Gdip_MultiplyLinearGrBrushTransform(pLinearGradientBrush, hMatrix, matrixOrder:=0) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipMultiplyLineTransform", Ptr, pLinearGradientBrush, Ptr, hMatrix, "int", matrixOrder)
}
Gdip_TranslateLinearGrBrushTransform(pLinearGradientBrush, X, Y, matrixOrder:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipTranslateLineTransform", Ptr, pLinearGradientBrush, "float", X, "float", Y, "int", matrixOrder)
}
Gdip_RotateLinearGrBrushTransform(pLinearGradientBrush, Angle, matrixOrder:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipRotateLineTransform", Ptr, pLinearGradientBrush, "float", Angle, "int", matrixOrder)
}
Gdip_SetLinearGrBrushTransform(pLinearGradientBrush, pMatrix) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetLineTransform", Ptr, pLinearGradientBrush, Ptr, pMatrix)
}
Gdip_GetLinearGrBrushTransform(pLineGradientBrush) {
Static Ptr := "UPtr"
pMatrix := 0
DllCall("gdiplus\GdipGetLineTransform", Ptr, pLineGradientBrush, "UPtr*", pMatrix)
Return pMatrix
}
Gdip_RotateLinearGrBrushAtCenter(pLinearGradientBrush, Angle, MatrixOrder:=1) {
Rect := Gdip_GetLinearGrBrushRect(pLinearGradientBrush)
cX := Rect.x + (Rect.w / 2)
cY := Rect.y + (Rect.h / 2)
pMatrix := Gdip_CreateMatrix()
Gdip_TranslateMatrix(pMatrix, -cX , -cY)
Gdip_RotateMatrix(pMatrix, Angle, MatrixOrder)
Gdip_TranslateMatrix(pMatrix, cX, cY, MatrixOrder)
E := Gdip_SetLinearGrBrushTransform(pLinearGradientBrush, pMatrix)
Gdip_DeleteMatrix(pMatrix)
Return E
}
Gdip_GetLinearGrBrushWrapMode(pLinearGradientBrush) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetLineWrapMode", Ptr, pLinearGradientBrush, "int*", result)
If E
return -1
Return result
}
Gdip_SetLinearGrBrushLinearBlend(pLinearGradientBrush, nFocus, nScale) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetLineLinearBlend", Ptr, pLinearGradientBrush, "float", nFocus, "float", nScale)
}
Gdip_SetLinearGrBrushSigmaBlend(pLinearGradientBrush, nFocus, nScale) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetLineSigmaBlend", Ptr, pLinearGradientBrush, "float", nFocus, "float", nScale)
}
Gdip_SetLinearGrBrushWrapMode(pLinearGradientBrush, WrapMode) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetLineWrapMode", Ptr, pLinearGradientBrush, "int", WrapMode)
}
Gdip_GetLinearGrBrushBlendCount(pLinearGradientBrush) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetLineBlendCount", Ptr, pLinearGradientBrush, "int*", result)
If E
return -1
Return result
}
Gdip_SetLinearGrBrushPresetBlend(pBrush, pA, pB, pC, pD, clr1, clr2, clr3, clr4) {
Static Ptr := "UPtr"
CreateRectF(POSITIONS, pA, pB, pC, pD)
CreateRect(COLORS, clr1, clr2, clr3, clr4)
E := DllCall("gdiplus\GdipSetLinePresetBlend", Ptr, pBrush, "Ptr", &COLORS, "Ptr", &POSITIONS, "Int", 4)
Return E
}
Gdip_CloneBrush(pBrush) {
pBrushClone := 0
gdipLastError := DllCall("gdiplus\GdipCloneBrush", "UPtr", pBrush, "UPtr*", pBrushClone)
return pBrushClone
}
Gdip_GetBrushType(pBrush) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetBrushType", Ptr, pBrush, "int*", result)
If E
return -1
Return result
}
Gdip_DeleteRegion(hRegion) {
If hRegion
return DllCall("gdiplus\GdipDeleteRegion", "UPtr", hRegion)
}
Gdip_DeletePen(pPen) {
If pPen
return DllCall("gdiplus\GdipDeletePen", "UPtr", pPen)
}
Gdip_DeleteBrush(pBrush) {
If pBrush
return DllCall("gdiplus\GdipDeleteBrush", "UPtr", pBrush)
}
Gdip_DisposeImage(pBitmap, noErr:=0) {
If (StrLen(pBitmap)<=2 && noErr=1)
Return 0
r := DllCall("gdiplus\GdipDisposeImage", "UPtr", pBitmap)
If (r=2 || r=1) && (noErr=1)
r := 0
Return r
}
Gdip_DeleteGraphics(pGraphics) {
If pGraphics
return DllCall("gdiplus\GdipDeleteGraphics", "UPtr", pGraphics)
}
Gdip_DisposeImageAttributes(ImageAttr) {
If ImageAttr
return DllCall("gdiplus\GdipDisposeImageAttributes", "UPtr", ImageAttr)
}
Gdip_DeleteFont(hFont) {
If hFont
return DllCall("gdiplus\GdipDeleteFont", "UPtr", hFont)
}
Gdip_DeleteStringFormat(hStringFormat) {
return DllCall("gdiplus\GdipDeleteStringFormat", "UPtr", hStringFormat)
}
Gdip_DeleteFontFamily(hFontFamily) {
If hFontFamily
return DllCall("gdiplus\GdipDeleteFontFamily", "UPtr", hFontFamily)
}
Gdip_DeletePrivateFontCollection(hFontCollection) {
If hFontCollection
return DllCall("gdiplus\GdipDeletePrivateFontCollection", "ptr*", hFontCollection)
}
Gdip_DeleteMatrix(hMatrix) {
If hMatrix
return DllCall("gdiplus\GdipDeleteMatrix", "UPtr", hMatrix)
}
Gdip_DrawOrientedString(pGraphics, String, FontName, Size, Style, X, Y, Width, Height, Angle:=0, pBrush:=0, pPen:=0, Align:=0, ScaleX:=1) {
If (!pBrush && !pPen)
Return -3
If RegExMatch(FontName, "^(.\:\\.)")
{
hFontCollection := Gdip_NewPrivateFontCollection()
hFontFamily := Gdip_CreateFontFamilyFromFile(FontName, hFontCollection)
} Else hFontFamily := Gdip_FontFamilyCreate(FontName)
If !hFontFamily
hFontFamily := Gdip_FontFamilyCreateGeneric(1)
If !hFontFamily
{
If hFontCollection
Gdip_DeletePrivateFontCollection(hFontCollection)
Return -1
}
FormatStyle := 0x4000
hStringFormat := Gdip_StringFormatCreate(FormatStyle)
If !hStringFormat
hStringFormat := Gdip_StringFormatGetGeneric(1)
If !hStringFormat
{
Gdip_DeleteFontFamily(hFontFamily)
If hFontCollection
Gdip_DeletePrivateFontCollection(hFontCollection)
Return -2
}
Gdip_SetStringFormatTrimming(hStringFormat, 3)
Gdip_SetStringFormatAlign(hStringFormat, Align)
pPath := Gdip_CreatePath()
E := Gdip_AddPathString(pPath, String, hFontFamily, Style, Size, hStringFormat, X, Y, Width, Height)
If (ScaleX>0 && ScaleX!=1)
{
hMatrix := Gdip_CreateMatrix()
Gdip_ScaleMatrix(hMatrix, ScaleX, 1)
Gdip_TransformPath(pPath, hMatrix)
Gdip_DeleteMatrix(hMatrix)
}
Gdip_RotatePathAtCenter(pPath, Angle)
If (!E && pBrush)
E := Gdip_FillPath(pGraphics, pBrush, pPath)
If (!E && pPen)
E := Gdip_DrawPath(pGraphics, pPen, pPath)
PathBounds := Gdip_GetPathWorldBounds(pPath)
Gdip_DeleteStringFormat(hStringFormat)
Gdip_DeleteFontFamily(hFontFamily)
Gdip_DeletePath(pPath)
If hFontCollection
Gdip_DeletePrivateFontCollection(hFontCollection)
Return E ? E : PathBounds
}
Gdip_TextToGraphics(pGraphics, Text, Options, Font:="Arial", Width:="", Height:="", Measure:=0, userBrush:=0, Unit:=0) {
Static Styles := "Regular|Bold|Italic|BoldItalic|Underline|Strikeout"
, Alignments := "Near|Left|Centre|Center|Far|Right"
OWidth := Width
IWidth := Width, IHeight:= Height
pattern_opts := (A_AhkVersion < "2") ? "iO)" : "i)"
RegExMatch(Options, pattern_opts "X([\-\d\.]+)(p*)", xpos)
RegExMatch(Options, pattern_opts "Y([\-\d\.]+)(p*)", ypos)
RegExMatch(Options, pattern_opts "W([\-\d\.]+)(p*)", PWidth)
RegExMatch(Options, pattern_opts "H([\-\d\.]+)(p*)", Height)
RegExMatch(Options, pattern_opts "C(?!(entre|enter))([a-f\d]+)", Colour)
RegExMatch(Options, pattern_opts "Top|Up|Bottom|Down|vCentre|vCenter", vPos)
RegExMatch(Options, pattern_opts "NoWrap", NoWrap)
RegExMatch(Options, pattern_opts "R(\d)", Rendering)
RegExMatch(Options, pattern_opts "S(\d+)(p*)", Size)
Width := PWidth
if Colour && IsInteger(Colour[2]) && !Gdip_DeleteBrush(Gdip_CloneBrush(Colour[2]))
{
PassBrush := 1
pBrush := Colour[2]
}
if !(IWidth && IHeight) && ((xpos && xpos[2]) || (ypos && ypos[2]) || (Width && Width[2]) || (Height && Height[2]) || (Size && Size[2]))
return -1
Style := 0
For eachStyle, valStyle in StrSplit(Styles, "|")
{
if RegExMatch(Options, "\b" valStyle)
Style |= (valStyle != "StrikeOut") ? (A_Index-1) : 8
}
Align := 0
For eachAlignment, valAlignment in StrSplit(Alignments, "|")
{
if RegExMatch(Options, "\b" valAlignment)
Align |= A_Index//2.1
}
xpos := (xpos && (xpos[1] != "")) ? xpos[2] ? IWidth*(xpos[1]/100) : xpos[1] : 0
ypos := (ypos && (ypos[1] != "")) ? ypos[2] ? IHeight*(ypos[1]/100) : ypos[1] : 0
Width := (Width && Width[1]) ? Width[2] ? IWidth*(Width[1]/100) : Width[1] : IWidth
Height := (Height && Height[1]) ? Height[2] ? IHeight*(Height[1]/100) : Height[1] : IHeight
If !PassBrush
Colour := "0x" (Colour && Colour[2] ? Colour[2] : "ff000000")
Rendering := (Rendering && (Rendering[1] >= 0) && (Rendering[1] <= 5)) ? Rendering[1] : 4
Size := (Size && (Size[1] > 0)) ? Size[2] ? IHeight*(Size[1]/100) : Size[1] : 12
If RegExMatch(Font, "^(.\:\\.)")
{
hFontCollection := Gdip_NewPrivateFontCollection()
hFontFamily := Gdip_CreateFontFamilyFromFile(Font, hFontCollection)
} Else hFontFamily := Gdip_FontFamilyCreate(Font)
If !hFontFamily
hFontFamily := Gdip_FontFamilyCreateGeneric(1)
hFont := Gdip_FontCreate(hFontFamily, Size, Style, Unit)
FormatStyle := NoWrap ? 0x4000 | 0x1000 : 0x4000
hStringFormat := Gdip_StringFormatCreate(FormatStyle)
If !hStringFormat
hStringFormat := Gdip_StringFormatGetGeneric(1)
pBrush := PassBrush ? pBrush : Gdip_BrushCreateSolid(Colour)
if !(hFontFamily && hFont && hStringFormat && pBrush && pGraphics)
{
E := !pGraphics ? -2 : !hFontFamily ? -3 : !hFont ? -4 : !hStringFormat ? -5 : !pBrush ? -6 : 0
If pBrush
Gdip_DeleteBrush(pBrush)
If hStringFormat
Gdip_DeleteStringFormat(hStringFormat)
If hFont
Gdip_DeleteFont(hFont)
If hFontFamily
Gdip_DeleteFontFamily(hFontFamily)
If hFontCollection
Gdip_DeletePrivateFontCollection(hFontCollection)
return E
}
CreateRectF(RC, xpos, ypos, Width, Height)
Gdip_SetStringFormatAlign(hStringFormat, Align)
If InStr(Options, "autotrim")
Gdip_SetStringFormatTrimming(hStringFormat, 3)
Gdip_SetTextRenderingHint(pGraphics, Rendering)
ReturnRC := Gdip_MeasureString(pGraphics, Text, hFont, hStringFormat, RC)
ReturnRCtest := StrSplit(ReturnRC, "|")
testX := Floor(ReturnRCtest[1]) - 2
If (testX>xpos && NoWrap && (PWidth>2 || OWidth>2))
{
nxpos := Floor(xpos - (testX - xpos))
CreateRectF(RC, nxpos, ypos, Width, Height)
ReturnRC := Gdip_MeasureString(pGraphics, Text, hFont, hStringFormat, RC)
}
If vPos
{
ReturnRC := StrSplit(ReturnRC, "|")
if (vPos[0] = "vCentre") || (vPos[0] = "vCenter")
ypos += (Height-ReturnRC[4])//2
else if (vPos[0] = "Top") || (vPos[0] = "Up")
ypos += 0
else if (vPos[0] = "Bottom") || (vPos[0] = "Down")
ypos += Height-ReturnRC[4]
CreateRectF(RC, xpos, ypos, Width, ReturnRC[4])
ReturnRC := Gdip_MeasureString(pGraphics, Text, hFont, hStringFormat, RC)
}
thisBrush := userBrush ? userBrush : pBrush
if !Measure
_E := Gdip_DrawString(pGraphics, Text, hFont, hStringFormat, thisBrush, RC)
if !PassBrush
Gdip_DeleteBrush(pBrush)
Gdip_DeleteStringFormat(hStringFormat)
Gdip_DeleteFont(hFont)
Gdip_DeleteFontFamily(hFontFamily)
If hFontCollection
Gdip_DeletePrivateFontCollection(hFontCollection)
return _E ? _E : ReturnRC
}
Gdip_DrawString(pGraphics, sString, hFont, hStringFormat, pBrush, ByRef RectF) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipDrawString"
, Ptr, pGraphics
, "WStr", sString
, "int", -1
, Ptr, hFont
, Ptr, &RectF
, Ptr, hStringFormat
, Ptr, pBrush)
}
Gdip_MeasureString(pGraphics, sString, hFont, hStringFormat, ByRef RectF) {
Static Ptr := "UPtr"
VarSetCapacity(RC, 16)
Chars := 0
Lines := 0
DllCall("gdiplus\GdipMeasureString"
, Ptr, pGraphics
, "WStr", sString
, "int", -1
, Ptr, hFont
, Ptr, &RectF
, Ptr, hStringFormat
, Ptr, &RC
, "uint*", Chars
, "uint*", Lines)
return &RC ? NumGet(RC, 0, "float") "|" NumGet(RC, 4, "float") "|" NumGet(RC, 8, "float") "|" NumGet(RC, 12, "float") "|" Chars "|" Lines : 0
}
Gdip_DrawStringAlongPolygon(pGraphics, String, FontName, FontSize, Style, pBrush, DriverPoints:=0, pPath:=0, minDist:=0, flatness:=4, hMatrix:=0, Unit:=0) {
If (!minDist || minDist<1)
minDist := FontSize//4 + 1
If (pPath && !DriverPoints)
{
newPath := Gdip_ClonePath(pPath)
Gdip_PathOutline(newPath, flatness)
DriverPoints := Gdip_GetPathPoints(newPath)
Gdip_DeletePath(newPath)
If !DriverPoints
Return -5
}
If (!pPath && !DriverPoints)
Return -4
If RegExMatch(FontName, "^(.\:\\.)")
{
hFontCollection := Gdip_NewPrivateFontCollection()
hFontFamily := Gdip_CreateFontFamilyFromFile(FontName, hFontCollection)
} Else hFontFamily := Gdip_FontFamilyCreate(FontName)
If !hFontFamily
hFontFamily := Gdip_FontFamilyCreateGeneric(1)
If !hFontFamily
{
If hFontCollection
Gdip_DeletePrivateFontCollection(hFontCollection)
Return -1
}
hFont := Gdip_FontCreate(hFontFamily, FontSize, Style, Unit)
If !hFont
{
If hFontCollection
Gdip_DeletePrivateFontCollection(hFontCollection)
Gdip_DeleteFontFamily(hFontFamily)
Return -2
}
Points := StrSplit(DriverPoints, "|")
PointsCount := Points.Length()
If (PointsCount<2)
{
If hFontCollection
Gdip_DeletePrivateFontCollection(hFontCollection)
Gdip_DeleteFont(hFont)
Gdip_DeleteFontFamily(hFontFamily)
Return -3
}
txtLen := StrLen(String)
If (PointsCount<txtLen)
{
loopsMax := txtLen * 3
newDriverPoints := DriverPoints
Loop %loopsMax%
{
newDriverPoints := GenerateIntermediatePoints(newDriverPoints, minDist, totalResult)
If (totalResult>=txtLen)
Break
}
String := SubStr(String, 1, totalResult)
} Else newDriverPoints := DriverPoints
E := Gdip_DrawDrivenString(pGraphics, String, hFont, pBrush, newDriverPoints, 1, hMatrix)
Gdip_DeleteFont(hFont)
Gdip_DeleteFontFamily(hFontFamily)
If hFontCollection
Gdip_DeletePrivateFontCollection(hFontCollection)
return E
}
GenerateIntermediatePoints(PointsList, minDist, ByRef resultPointsCount) {
AllPoints := StrSplit(PointsList, "|")
PointsCount := AllPoints.Length()
thizIndex := 0.5
resultPointsCount := 0
loopsMax := PointsCount*2
Loop %loopsMax%
{
thizIndex += 0.5
thisIndex := InStr(thizIndex, ".5") ? thizIndex : Trim(Round(thizIndex))
thisPoint := AllPoints[thisIndex]
theseCoords := StrSplit(thisPoint, ",")
If (theseCoords[1]!="" && theseCoords[2]!="")
{
resultPointsCount++
newPointsList .= theseCoords[1] "," theseCoords[2] "|"
} Else
{
aIndex := Trim(Round(thizIndex - 0.5))
bIndex := Trim(Round(thizIndex + 0.5))
theseAcoords := StrSplit(AllPoints[aIndex], ",")
theseBcoords := StrSplit(AllPoints[bIndex], ",")
If (theseAcoords[1]!="" && theseAcoords[2]!="")
&& (theseBcoords[1]!="" && theseBcoords[2]!="")
{
newPosX := (theseAcoords[1] + theseBcoords[1])//2
newPosY := (theseAcoords[2] + theseBcoords[2])//2
distPosX := newPosX - theseAcoords[1]
distPosY := newPosY - theseAcoords[2]
If (distPosX>minDist || distPosY>minDist)
{
newPointsList .= newPosX "," newPosY "|"
resultPointsCount++
}
}
}
}
If !newPointsList
Return PointsList
Return Trim(newPointsList, "|")
}
Gdip_DrawDrivenString(pGraphics, String, hFont, pBrush, DriverPoints, Flags:=1, hMatrix:=0) {
txtLen := -1
Static Ptr := "UPtr"
iCount := CreatePointsF(PointsF, DriverPoints)
return DllCall("gdiplus\GdipDrawDriverString", Ptr, pGraphics, "UPtr", &String, "int", txtLen, Ptr, hFont, Ptr, pBrush, Ptr, &PointsF, "int", Flags, Ptr, hMatrix)
}
Gdip_GetStringFormatFlags(hStringFormat) {
result := 0
E := DllCall("gdiplus\GdipGetStringFormatFlags", "UPtr", hStringFormat, "int*", result)
If E
Return -1
Return result
}
Gdip_StringFormatCreate(FormatFlags:=0, LangID:=0) {
hStringFormat := 0
E := DllCall("gdiplus\GdipCreateStringFormat", "int", FormatFlags, "int", LangID, "UPtr*", hStringFormat)
return hStringFormat
}
Gdip_CloneStringFormat(hStringFormat) {
Static Ptr := "UPtr"
newHStringFormat := 0
gdipLastError := DllCall("gdiplus\GdipCloneStringFormat", Ptr, hStringFormat, "uint*", newHStringFormat)
Return newHStringFormat
}
Gdip_StringFormatGetGeneric(whichFormat:=0) {
hStringFormat := 0
If (whichFormat=1)
gdipLastError := DllCall("gdiplus\GdipStringFormatGetGenericTypographic", "UPtr*", hStringFormat)
Else
gdipLastError := DllCall("gdiplus\GdipStringFormatGetGenericDefault", "UPtr*", hStringFormat)
Return hStringFormat
}
Gdip_SetStringFormatAlign(hStringFormat, Align) {
return DllCall("gdiplus\GdipSetStringFormatAlign", "UPtr", hStringFormat, "int", Align)
}
Gdip_GetStringFormatAlign(hStringFormat) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetStringFormatAlign", Ptr, hStringFormat, "int*", result)
If E
Return -1
Return result
}
Gdip_GetStringFormatLineAlign(hStringFormat) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetStringFormatLineAlign", Ptr, hStringFormat, "int*", result)
If E
Return -1
Return result
}
Gdip_GetStringFormatDigitSubstitution(hStringFormat) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetStringFormatDigitSubstitution", Ptr, hStringFormat, "ushort*", 0, "int*", result)
If E
Return -1
Return result
}
Gdip_GetStringFormatHotkeyPrefix(hStringFormat) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetStringFormatHotkeyPrefix", Ptr, hStringFormat, "int*", result)
If E
Return -1
Return result
}
Gdip_GetStringFormatTrimming(hStringFormat) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetStringFormatTrimming", Ptr, hStringFormat, "int*", result)
If E
Return -1
Return result
}
Gdip_SetStringFormatLineAlign(hStringFormat, StringAlign) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipSetStringFormatLineAlign", Ptr, hStringFormat, "int", StringAlign)
}
Gdip_SetStringFormatDigitSubstitution(hStringFormat, DigitSubstitute, LangID:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetStringFormatDigitSubstitution", Ptr, hStringFormat, "ushort", LangID, "int", DigitSubstitute)
}
Gdip_SetStringFormatFlags(hStringFormat, Flags) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetStringFormatFlags", Ptr, hStringFormat, "int", Flags)
}
Gdip_SetStringFormatHotkeyPrefix(hStringFormat, PrefixProcessMode) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetStringFormatHotkeyPrefix", Ptr, hStringFormat, "int", PrefixProcessMode)
}
Gdip_SetStringFormatTrimming(hStringFormat, TrimMode) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetStringFormatTrimming", Ptr, hStringFormat, "int", TrimMode)
}
Gdip_FontCreate(hFontFamily, Size, Style:=0, Unit:=0) {
hFont := 0
DllCall("gdiplus\GdipCreateFont", "UPtr", hFontFamily, "float", Size, "int", Style, "int", Unit, "UPtr*", hFont)
return hFont
}
Gdip_FontFamilyCreate(FontName) {
hFontFamily := 0
_E := DllCall("gdiplus\GdipCreateFontFamilyFromName"
, "WStr", FontName, "uint", 0
, "UPtr*", hFontFamily)
return hFontFamily
}
Gdip_NewPrivateFontCollection() {
hFontCollection := 0
DllCall("gdiplus\GdipNewPrivateFontCollection", "ptr*", hFontCollection)
Return hFontCollection
}
Gdip_CreateFontFamilyFromFile(FontFile, hFontCollection, FontName:="") {
If !hFontCollection
Return
hFontFamily := 0
E := DllCall("gdiplus\GdipPrivateAddFontFile", "ptr", hFontCollection, "str", FontFile)
if (FontName="" && !E)
{
VarSetCapacity(pFontFamily, 10, 0)
DllCall("gdiplus\GdipGetFontCollectionFamilyList", "ptr", hFontCollection, "int", 1, "ptr", &pFontFamily, "int*", found)
VarSetCapacity(FontName, 100)
DllCall("gdiplus\GdipGetFamilyName", "ptr", NumGet(pFontFamily, 0, "ptr"), "str", FontName, "ushort", 1033)
}
If !E
DllCall("gdiplus\GdipCreateFontFamilyFromName", "str", FontName, "ptr", hFontCollection, "uint*", hFontFamily)
Return hFontFamily
}
Gdip_FontFamilyCreateGeneric(whichStyle) {
hFontFamily := 0
If (whichStyle=0)
DllCall("gdiplus\GdipGetGenericFontFamilyMonospace", "UPtr*", hFontFamily)
Else If (whichStyle=1)
DllCall("gdiplus\GdipGetGenericFontFamilySansSerif", "UPtr*", hFontFamily)
Else If (whichStyle=2)
DllCall("gdiplus\GdipGetGenericFontFamilySerif", "UPtr*", hFontFamily)
Return hFontFamily
}
Gdip_CreateFontFromDC(hDC) {
pFont := 0
gdipLastError := DllCall("gdiplus\GdipCreateFontFromDC", "UPtr", hDC, "UPtr*", pFont)
Return pFont
}
Gdip_CreateFontFromLogfontW(hDC, LogFont) {
pFont := 0
gdipLastError := DllCall("Gdiplus\GdipCreateFontFromLogfontW", "Ptr", hDC, "Ptr", LogFont, "UPtrP", pFont)
return pFont
}
Gdip_GetFontHeight(hFont, pGraphics:=0) {
result := 0
gdipLastError := DllCall("gdiplus\GdipGetFontHeight", "UPtr", hFont, "UPtr", pGraphics, "float*", result)
Return result
}
Gdip_GetFontHeightGivenDPI(hFont, DPI:=72) {
result := 0
gdipLastError := DllCall("gdiplus\GdipGetFontHeightGivenDPI", "UPtr", hFont, "float", DPI, "float*", result)
Return result
}
Gdip_GetFontSize(hFont) {
result := 0
gdipLastError := DllCall("gdiplus\GdipGetFontSize", "UPtr", hFont, "float*", result)
Return result
}
Gdip_GetFontStyle(hFont) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetFontStyle", Ptr, hFont, "int*", result)
If E
Return -1
Return result
}
Gdip_GetFontUnit(hFont) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetFontUnit", Ptr, hFont, "int*", result)
If E
Return -1
Return result
}
Gdip_CloneFont(hfont) {
Static Ptr := "UPtr"
newHFont := 0
gdipLastError := DllCall("gdiplus\GdipCloneFont", Ptr, hFont, "UPtr*", newHFont)
Return newHFont
}
Gdip_GetFontFamily(hFont) {
Static Ptr := "UPtr"
hFontFamily := 0
gdipLastError := DllCall("gdiplus\GdipGetFamily", Ptr, hFont, "UPtr*", hFontFamily)
Return hFontFamily
}
Gdip_CloneFontFamily(hFontFamily) {
Static Ptr := "UPtr"
newHFontFamily := 0
gdipLastError := DllCall("gdiplus\GdipCloneFontFamily", Ptr, hFontFamily, "UPtr*", newHFontFamily)
Return newHFontFamily
}
Gdip_IsFontStyleAvailable(hFontFamily, Style) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipIsStyleAvailable", Ptr, hFontFamily, "int", Style, "Int*", result)
If E
Return -1
Return result
}
Gdip_GetFontFamilyCellScents(hFontFamily, ByRef Ascent, ByRef Descent, Style:=0) {
Static Ptr := "UPtr"
Ascent := 0
Descent := 0
E := DllCall("gdiplus\GdipGetCellAscent", Ptr, hFontFamily, "int", Style, "ushort*", Ascent)
E := DllCall("gdiplus\GdipGetCellDescent", Ptr, hFontFamily, "int", Style, "ushort*", Descent)
Return E
}
Gdip_GetFontFamilyEmHeight(hFontFamily, Style:=0) {
Static Ptr := "UPtr"
result := 0
gdipLastError := DllCall("gdiplus\GdipGetEmHeight", Ptr, hFontFamily, "int", Style, "ushort*", result)
Return result
}
Gdip_GetFontFamilyLineSpacing(hFontFamily, Style:=0) {
Static Ptr := "UPtr"
result := 0
gdipLastError := DllCall("gdiplus\GdipGetLineSpacing", Ptr, hFontFamily, "int", Style, "ushort*", result)
Return result
}
Gdip_GetFontFamilyName(hFontFamily) {
Static Ptr := "UPtr"
VarSetCapacity(FontName, 90)
gdipLastError := DllCall("gdiplus\GdipGetFamilyName", Ptr, hFontFamily, "Ptr", &FontName, "ushort", 0)
Return FontName
}
Gdip_CreateAffineMatrix(m11, m12, m21, m22, x, y) {
hMatrix := 0
gdipLastError := DllCall("gdiplus\GdipCreateMatrix2", "float", m11, "float", m12, "float", m21, "float", m22, "float", x, "float", y, "UPtr*", hMatrix)
return hMatrix
}
Gdip_CreateMatrix() {
hMatrix := 0
gdipLastError := DllCall("gdiplus\GdipCreateMatrix", "UPtr*", hMatrix)
return hMatrix
}
Gdip_InvertMatrix(hMatrix) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipInvertMatrix", Ptr, hMatrix)
}
Gdip_IsMatrixEqual(hMatrixA, hMatrixB) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipIsMatrixEqual", Ptr, hMatrixA, Ptr, hMatrixB, "int*", result)
If E
Return -1
Return result
}
Gdip_IsMatrixIdentity(hMatrix) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipIsMatrixIdentity", Ptr, hMatrix, "int*", result)
If E
Return -1
Return result
}
Gdip_IsMatrixInvertible(hMatrix) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipIsMatrixInvertible", Ptr, hMatrix, "int*", result)
If E
Return -1
Return result
}
Gdip_MultiplyMatrix(hMatrixA, hMatrixB, matrixOrder) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipMultiplyMatrix", Ptr, hMatrixA, Ptr, hMatrixB, "int", matrixOrder)
}
Gdip_CloneMatrix(hMatrix) {
Static Ptr := "UPtr"
newHMatrix := 0
gdipLastError := DllCall("gdiplus\GdipCloneMatrix", Ptr, hMatrix, "UPtr*", newHMatrix)
return newHMatrix
}
Gdip_CreatePath(BrushMode:=0) {
pPath := 0
gdipLastError := DllCall("gdiplus\GdipCreatePath", "int", BrushMode, "UPtr*", pPath)
return pPath
}
Gdip_AddPathEllipse(pPath, x, y, w, h) {
return DllCall("gdiplus\GdipAddPathEllipse", "UPtr", pPath, "float", x, "float", y, "float", w, "float", h)
}
Gdip_AddPathRectangle(pPath, x, y, w, h) {
return DllCall("gdiplus\GdipAddPathRectangle", "UPtr", pPath, "float", x, "float", y, "float", w, "float", h)
}
Gdip_AddPathRoundedRectangle(pPath, x, y, w, h, r) {
E := 0
r := (w <= h) ? (r < w / 2) ? r : w / 2 : (r < h / 2) ? r : h / 2
If (E := Gdip_AddPathRectangle(pPath, x+r, y, w-(2*r), r))
Return E
If (E := Gdip_AddPathRectangle(pPath, x+r, y+h-r, w-(2*r), r))
Return E
If (E := Gdip_AddPathRectangle(pPath, x, y+r, r, h-(2*r)))
Return E
If (E := Gdip_AddPathRectangle(pPath, x+w-r, y+r, r, h-(2*r)))
Return E
If (E := Gdip_AddPathRectangle(pPath, x+r, y+r, w-(2*r), h-(2*r)))
Return E
If (E := Gdip_AddPathPie(pPath, x, y, 2*r, 2*r, 180, 90))
Return E
If (E := Gdip_AddPathPie(pPath, x+w-(2*r), y, 2*r, 2*r, 270, 90))
Return E
If (E := Gdip_AddPathPie(pPath, x, y+h-(2*r), 2*r, 2*r, 90, 90))
Return E
If (E := Gdip_AddPathPie(pPath, x+w-(2*r), y+h-(2*r), 2*r, 2*r, 0, 90))
Return E
Return E
}
Gdip_AddPathPolygon(pPath, Points) {
Static Ptr := "UPtr"
iCount := CreatePointsF(PointsF, Points)
return DllCall("gdiplus\GdipAddPathPolygon", Ptr, pPath, Ptr, &PointsF, "int", iCount)
}
Gdip_AddPathClosedCurve(pPath, Points, Tension:=1) {
iCount := CreatePointsF(PointsF, Points)
If Tension
return DllCall("gdiplus\GdipAddPathClosedCurve2", "UPtr", pPath, "UPtr", &PointsF, "int", iCount, "float", Tension)
Else
return DllCall("gdiplus\GdipAddPathClosedCurve", "UPtr", pPath, "UPtr", &PointsF, "int", iCount)
}
Gdip_AddPathCurve(pPath, Points, Tension:="") {
iCount := CreatePointsF(PointsF, Points)
If Tension
return DllCall("gdiplus\GdipAddPathCurve2", "UPtr", pPath, "UPtr", &PointsF, "int", iCount, "float", Tension)
Else
return DllCall("gdiplus\GdipAddPathCurve", "UPtr", pPath, "UPtr", &PointsF, "int", iCount)
}
Gdip_AddPathToPath(pPathA, pPathB, fConnect) {
return DllCall("gdiplus\GdipAddPathCurve2", "UPtr", pPathA, "UPtr", pPathB, "int", fConnect)
}
Gdip_AddPathStringSimplified(pPath, String, FontName, Size, Style, X, Y, Width, Height, Align:=0, NoWrap:=0) {
FormatStyle := NoWrap ? 0x4000 | 0x1000 : 0x4000
If RegExMatch(FontName, "^(.\:\\.)")
{
hFontCollection := Gdip_NewPrivateFontCollection()
hFontFamily := Gdip_CreateFontFamilyFromFile(FontName, hFontCollection)
} Else hFontFamily := Gdip_FontFamilyCreate(FontName)
If !hFontFamily
hFontFamily := Gdip_FontFamilyCreateGeneric(1)
If !hFontFamily
{
If hFontCollection
Gdip_DeletePrivateFontCollection(hFontCollection)
Return -1
}
hStringFormat := Gdip_StringFormatCreate(FormatStyle)
If !hStringFormat
hStringFormat := Gdip_StringFormatGetGeneric(1)
If !hStringFormat
{
Gdip_DeleteFontFamily(hFontFamily)
If hFontCollection
Gdip_DeletePrivateFontCollection(hFontCollection)
Return -2
}
Gdip_SetStringFormatTrimming(hStringFormat, 3)
Gdip_SetStringFormatAlign(hStringFormat, Align)
E := Gdip_AddPathString(pPath, String, hFontFamily, Style, Size, hStringFormat, X, Y, Width, Height)
Gdip_DeleteStringFormat(hStringFormat)
Gdip_DeleteFontFamily(hFontFamily)
If hFontCollection
Gdip_DeletePrivateFontCollection(hFontCollection)
Return E
}
Gdip_AddPathString(pPath, String, hFontFamily, Style, Size, hStringFormat, X, Y, W, H) {
Static Ptr := "UPtr"
CreateRectF(RectF, X, Y, W, H)
E := DllCall("gdiplus\GdipAddPathString", Ptr, pPath, "WStr", String, "int", -1, Ptr, hFontFamily, "int", Style, "float", Size, Ptr, &RectF, Ptr, hStringFormat)
Return E
}
Gdip_SetPathFillMode(pPath, FillMode) {
return DllCall("gdiplus\GdipSetPathFillMode", "UPtr", pPath, "int", FillMode)
}
Gdip_GetPathFillMode(pPath) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetPathFillMode", Ptr, pPath, "int*", result)
If E
Return -1
Return result
}
Gdip_GetPathLastPoint(pPath, ByRef X, ByRef Y) {
Static Ptr := "UPtr"
VarSetCapacity(PointF, 8, 0)
E := DllCall("gdiplus\GdipGetPathLastPoint", Ptr, pPath, "UPtr", &PointF)
If !E
{
x := NumGet(PointF, 0, "float")
y := NumGet(PointF, 4, "float")
}
Return E
}
Gdip_GetPathPointsCount(pPath) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetPointCount", Ptr, pPath, "int*", result)
If E
Return -1
Return result
}
Gdip_GetPathPoints(pPath) {
PointsCount := Gdip_GetPathPointsCount(pPath)
If (PointsCount=-1)
Return 0
Static Ptr := "UPtr"
VarSetCapacity(PointsF, 8 * PointsCount, 0)
DllCall("gdiplus\GdipGetPathPoints", Ptr, pPath, Ptr, &PointsF, "intP", PointsCount)
Loop %PointsCount%
{
A := NumGet(&PointsF, 8*(A_Index-1), "float")
B := NumGet(&PointsF, (8*(A_Index-1))+4, "float")
printList .= A "," B "|"
}
Return Trim(printList, "|")
}
Gdip_FlattenPath(pPath, flatness, hMatrix:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipFlattenPath", Ptr, pPath, Ptr, hMatrix, "float", flatness)
}
Gdip_WidenPath(pPath, pPen, hMatrix:=0, Flatness:=1) {
return DllCall("gdiplus\GdipWidenPath", "UPtr", pPath, "uint", pPen, "UPtr", hMatrix, "float", Flatness)
}
Gdip_PathOutline(pPath, flatness:=1, hMatrix:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipWindingModeOutline", Ptr, pPath, Ptr, hMatrix, "float", flatness)
}
Gdip_ResetPath(pPath) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipResetPath", Ptr, pPath)
}
Gdip_ReversePath(pPath) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipReversePath", Ptr, pPath)
}
Gdip_IsOutlineVisiblePathPoint(pGraphics, pPath, pPen, X, Y) {
result := 0
E := DllCall("gdiplus\GdipIsOutlineVisiblePathPoint", Ptr, pPath, "float", X, "float", Y, Ptr, pPen, Ptr, pGraphics, "int*", result)
If E
Return -1
Return result
}
Gdip_IsVisiblePathPoint(pPath, x, y, pGraphics) {
result := 0
E := DllCall("gdiplus\GdipIsVisiblePathPoint", "UPtr", pPath, "float", x, "float", y, "UPtr", pGraphics, "UPtr*", result)
If E
return -1
return result
}
Gdip_DeletePath(pPath) {
If pPath
return DllCall("gdiplus\GdipDeletePath", "UPtr", pPath)
}
Gdip_SetTextRenderingHint(pGraphics, RenderingHint) {
If !pGraphics
Return 2
Return DllCall("gdiplus\GdipSetTextRenderingHint", "UPtr", pGraphics, "int", RenderingHint)
}
Gdip_SetInterpolationMode(pGraphics, InterpolationMode) {
If !pGraphics
Return 2
Return DllCall("gdiplus\GdipSetInterpolationMode", "UPtr", pGraphics, "int", InterpolationMode)
}
Gdip_SetSmoothingMode(pGraphics, SmoothingMode) {
If !pGraphics
Return 2
Return DllCall("gdiplus\GdipSetSmoothingMode", "UPtr", pGraphics, "int", SmoothingMode)
}
Gdip_SetCompositingMode(pGraphics, CompositingMode) {
If !pGraphics
Return 2
return DllCall("gdiplus\GdipSetCompositingMode", "UPtr", pGraphics, "int", CompositingMode)
}
Gdip_SetCompositingQuality(pGraphics, CompositionQuality) {
If !pGraphics
Return 2
Return DllCall("gdiplus\GdipSetCompositingQuality", "UPtr", pGraphics, "int", CompositionQuality)
}
Gdip_SetPageScale(pGraphics, Scale) {
If !pGraphics
Return 2
Return DllCall("gdiplus\GdipSetPageScale", "UPtr", pGraphics, "float", Scale)
}
Gdip_SetPageUnit(pGraphics, Unit) {
If !pGraphics
Return 2
Return DllCall("gdiplus\GdipSetPageUnit", "UPtr", pGraphics, "int", Unit)
}
Gdip_SetPixelOffsetMode(pGraphics, PixelOffsetMode) {
If !pGraphics
Return 2
Return DllCall("gdiplus\GdipSetPixelOffsetMode", "UPtr", pGraphics, "int", PixelOffsetMode)
}
Gdip_SetRenderingOrigin(pGraphics, X, Y) {
If !pGraphics
Return 2
Return DllCall("gdiplus\GdipSetRenderingOrigin", "UPtr", pGraphics, "int", X, "int", Y)
}
Gdip_SetTextContrast(pGraphics, Contrast) {
If !pGraphics
Return 2
Return DllCall("gdiplus\GdipSetTextContrast", "UPtr", pGraphics, "uint", Contrast)
}
Gdip_RestoreGraphics(pGraphics, State) {
return DllCall("Gdiplus\GdipRestoreGraphics", "UPtr", pGraphics, "UInt", State)
}
Gdip_SaveGraphics(pGraphics) {
State := 0
DllCall("Gdiplus\GdipSaveGraphics", "Ptr", pGraphics, "UIntP", State)
return State
}
Gdip_GetTextContrast(pGraphics) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetTextContrast", Ptr, pGraphics, "uint*", result)
If E
return -1
Return result
}
Gdip_GetCompositingMode(pGraphics) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetCompositingMode", Ptr, pGraphics, "int*", result)
If E
return -1
Return result
}
Gdip_GetCompositingQuality(pGraphics) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetCompositingQuality", Ptr, pGraphics, "int*", result)
If E
return -1
Return result
}
Gdip_GetInterpolationMode(pGraphics) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetInterpolationMode", Ptr, pGraphics, "int*", result)
If E
return -1
Return result
}
Gdip_GetSmoothingMode(pGraphics) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetSmoothingMode", Ptr, pGraphics, "int*", result)
If E
return -1
Return result
}
Gdip_GetPageScale(pGraphics) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetPageScale", Ptr, pGraphics, "float*", result)
If E
return -1
Return result
}
Gdip_GetPageUnit(pGraphics) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetPageUnit", Ptr, pGraphics, "int*", result)
If E
return -1
Return result
}
Gdip_GetPixelOffsetMode(pGraphics) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetPixelOffsetMode", Ptr, pGraphics, "int*", result)
If E
return -1
Return result
}
Gdip_GetRenderingOrigin(pGraphics, ByRef X, ByRef Y) {
Static Ptr := "UPtr"
x := 0
y := 0
return DllCall("gdiplus\GdipGetRenderingOrigin", Ptr, pGraphics, "uint*", X, "uint*", Y)
}
Gdip_GetTextRenderingHint(pGraphics) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetTextRenderingHint", Ptr, pGraphics, "int*", result)
If E
return -1
Return result
}
Gdip_RotateWorldTransform(pGraphics, Angle, MatrixOrder:=0) {
return DllCall("gdiplus\GdipRotateWorldTransform", "UPtr", pGraphics, "float", Angle, "int", MatrixOrder)
}
Gdip_ScaleWorldTransform(pGraphics, ScaleX, ScaleY, MatrixOrder:=0) {
return DllCall("gdiplus\GdipScaleWorldTransform", "UPtr", pGraphics, "float", ScaleX, "float", ScaleY, "int", MatrixOrder)
}
Gdip_TranslateWorldTransform(pGraphics, x, y, MatrixOrder:=0) {
return DllCall("gdiplus\GdipTranslateWorldTransform", "UPtr", pGraphics, "float", x, "float", y, "int", MatrixOrder)
}
Gdip_MultiplyWorldTransform(pGraphics, hMatrix, matrixOrder:=0) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipMultiplyWorldTransform", Ptr, pGraphics, Ptr, hMatrix, "int", matrixOrder)
}
Gdip_ResetWorldTransform(pGraphics) {
return DllCall("gdiplus\GdipResetWorldTransform", "UPtr", pGraphics)
}
Gdip_ResetPageTransform(pGraphics) {
return DllCall("gdiplus\GdipResetPageTransform", "UPtr", pGraphics)
}
Gdip_SetWorldTransform(pGraphics, hMatrix) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetWorldTransform", Ptr, pGraphics, Ptr, hMatrix)
}
Gdip_GetRotatedTranslation(Width, Height, Angle, ByRef xTranslation, ByRef yTranslation) {
pi := 3.14159, TAngle := Angle*(pi/180)
Bound := (Angle >= 0) ? Mod(Angle, 360) : 360-Mod(-Angle, -360)
if ((Bound >= 0) && (Bound <= 90))
xTranslation := Height*Sin(TAngle), yTranslation := 0
else if ((Bound > 90) && (Bound <= 180))
xTranslation := (Height*Sin(TAngle))-(Width*Cos(TAngle)), yTranslation := -Height*Cos(TAngle)
else if ((Bound > 180) && (Bound <= 270))
xTranslation := -(Width*Cos(TAngle)), yTranslation := -(Height*Cos(TAngle))-(Width*Sin(TAngle))
else if ((Bound > 270) && (Bound <= 360))
xTranslation := 0, yTranslation := -Width*Sin(TAngle)
}
Gdip_GetRotatedDimensions(Width, Height, Angle, ByRef RWidth, ByRef RHeight) {
Static pi := 3.14159
if !(Width && Height)
return -1
TAngle := Angle*(pi/180)
RWidth := Abs(Width*Cos(TAngle))+Abs(Height*Sin(TAngle))
RHeight := Abs(Width*Sin(TAngle))+Abs(Height*Cos(Tangle))
}
Gdip_GetRotatedEllipseDimensions(Width, Height, Angle, ByRef RWidth, ByRef RHeight) {
if !(Width && Height)
return -1
pPath := Gdip_CreatePath()
Gdip_AddPathEllipse(pPath, 0, 0, Width, Height)
pMatrix := Gdip_CreateMatrix()
Gdip_RotateMatrix(pMatrix, Angle, MatrixOrder)
E := Gdip_TransformPath(pPath, pMatrix)
Gdip_DeleteMatrix(pMatrix)
pathBounds := Gdip_GetPathWorldBounds(pPath)
Gdip_DeletePath(pPath)
RWidth := pathBounds.w
RHeight := pathBounds.h
Return E
}
Gdip_GetWorldTransform(pGraphics) {
Static Ptr := "UPtr"
hMatrix := 0
gdipLastError := DllCall("gdiplus\GdipGetWorldTransform", Ptr, pGraphics, "UPtr*", hMatrix)
Return hMatrix
}
Gdip_IsVisibleGraphPoint(pGraphics, X, Y) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipIsVisiblePoint", Ptr, pGraphics, "float", X, "float", Y, "int*", result)
If E
Return -1
Return result
}
Gdip_IsVisibleGraphRect(pGraphics, X, Y, Width, Height) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipIsVisibleRect", Ptr, pGraphics, "float", X, "float", Y, "float", Width, "float", Height, "int*", result)
If E
Return -1
Return result
}
Gdip_IsVisibleGraphRectEntirely(pGraphics, X, Y, Width, Height) {
a := Gdip_IsVisibleGraphPoint(pGraphics, X, Y)
b := Gdip_IsVisibleGraphPoint(pGraphics, X + Width, Y)
c := Gdip_IsVisibleGraphPoint(pGraphics, X + Width, Y + Height)
d := Gdip_IsVisibleGraphPoint(pGraphics, X, Y + Height)
If (a=1 && b=1 && c=1 && d=1)
Return 1
Else If (a=-1 || b=-1 || c=-1 || d=-1)
Return -1
Else
Return 0
}
Gdip_IsClipEmpty(pGraphics) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipIsClipEmpty", Ptr, pGraphics, "int*", result)
If E
Return -1
Return result
}
Gdip_IsVisibleClipEmpty(pGraphics) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipIsVisibleClipEmpty", Ptr, pGraphics, "uint*", result)
If E
Return -1
Return result
}
Gdip_SetClipFromGraphics(pGraphics, pGraphicsSrc, CombineMode:=0) {
return DllCall("gdiplus\GdipSetClipGraphics", "UPtr", pGraphics, "UPtr", pGraphicsSrc, "int", CombineMode)
}
Gdip_GetClipBounds(pGraphics) {
rData := {}
VarSetCapacity(RectF, 16, 0)
E := DllCall("gdiplus\GdipGetClipBounds", "UPtr", pGraphics, "UPtr", &RectF)
If (!E) {
rData.x := NumGet(&RectF, 0, "float")
, rData.y := NumGet(&RectF, 4, "float")
, rData.w := NumGet(&RectF, 8, "float")
, rData.h := NumGet(&RectF, 12, "float")
} Else {
Return E
}
return rData
}
Gdip_GetVisibleClipBounds(pGraphics) {
rData := {}
VarSetCapacity(RectF, 16, 0)
E := DllCall("gdiplus\GdipGetVisibleClipBounds", "UPtr", pGraphics, "UPtr", &RectF)
If (!E) {
rData.x := NumGet(&RectF, 0, "float")
, rData.y := NumGet(&RectF, 4, "float")
, rData.w := NumGet(&RectF, 8, "float")
, rData.h := NumGet(&RectF, 12, "float")
} Else {
Return E
}
return rData
}
Gdip_TranslateClip(pGraphics, dX, dY) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipTranslateClip", Ptr, pGraphics, "float", dX, "float", dY)
}
Gdip_ResetClip(pGraphics) {
return DllCall("gdiplus\GdipResetClip", "UPtr", pGraphics)
}
Gdip_GetClipRegion(pGraphics) {
Region := Gdip_CreateRegion()
E := DllCall("gdiplus\GdipGetClip", "UPtr", pGraphics, "UInt", Region)
If E
return -1
return Region
}
Gdip_SetClipRegion(pGraphics, Region, CombineMode:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetClipRegion", Ptr, pGraphics, Ptr, Region, "int", CombineMode)
}
Gdip_SetClipRect(pGraphics, x, y, w, h, CombineMode:=0) {
return DllCall("gdiplus\GdipSetClipRect", "UPtr", pGraphics, "float", x, "float", y, "float", w, "float", h, "int", CombineMode)
}
Gdip_SetClipPath(pGraphics, pPath, CombineMode:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetClipPath", Ptr, pGraphics, Ptr, pPath, "int", CombineMode)
}
Gdip_CreateRegion() {
hRegion := 0
gdipLastError := DllCall("gdiplus\GdipCreateRegion", "UInt*", hRegion)
return hRegion
}
Gdip_CombineRegionRegion(Region, Region2, CombineMode) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipCombineRegionRegion", Ptr, Region, Ptr, Region2, "int", CombineMode)
}
Gdip_CombineRegionRect(Region, x, y, w, h, CombineMode) {
Static Ptr := "UPtr"
CreateRectF(RectF, x, y, w, h)
return DllCall("gdiplus\GdipCombineRegionRect", Ptr, Region, Ptr, &RectF, "int", CombineMode)
}
Gdip_CombineRegionPath(Region, pPath, CombineMode) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipCombineRegionPath", Ptr, Region, Ptr, pPath, "int", CombineMode)
}
Gdip_CreateRegionPath(pPath) {
hRegion := 0
gdipLastError := DllCall("gdiplus\GdipCreateRegionPath", "UPtr", pPath, "UInt*", hRegion)
return hRegion
}
Gdip_CreateRegionRect(x, y, w, h) {
hRegion := 0
CreateRectF(RectF, x, y, w, h)
gdipLastError := DllCall("gdiplus\GdipCreateRegionRect", "UPtr", &RectF, "UInt*", hRegion)
return hRegion
}
Gdip_IsEmptyRegion(pGraphics, Region) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipIsEmptyRegion", Ptr, Region, Ptr, pGraphics, "uInt*", result)
If E
return -1
Return result
}
Gdip_IsEqualRegion(pGraphics, Region1, Region2) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipIsEqualRegion", Ptr, Region1, Ptr, Region2, Ptr, pGraphics, "uInt*", result)
If E
return -1
Return result
}
Gdip_IsInfiniteRegion(pGraphics, Region) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipIsInfiniteRegion", Ptr, Region, Ptr, pGraphics, "uInt*", result)
If E
return -1
Return result
}
Gdip_IsVisibleRegionPoint(pGraphics, Region, x, y) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipIsVisibleRegionPoint", Ptr, Region, "float", X, "float", Y, Ptr, pGraphics, "uInt*", result)
If E
return -1
Return result
}
Gdip_IsVisibleRegionRect(pGraphics, Region, x, y, width, height) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipIsVisibleRegionRect", Ptr, Region, "float", X, "float", Y, "float", Width, "float", Height, Ptr, pGraphics, "uInt*", result)
If E
return -1
Return result
}
Gdip_IsVisibleRegionRectEntirely(pGraphics, Region, x, y, width, height) {
a := Gdip_IsVisibleRegionPoint(pGraphics, Region, X, Y)
b := Gdip_IsVisibleRegionPoint(pGraphics, Region, X + Width, Y)
c := Gdip_IsVisibleRegionPoint(pGraphics, Region, X + Width, Y + Height)
d := Gdip_IsVisibleRegionPoint(pGraphics, Region, X, Y + Height)
If (a=1 && b=1 && c=1 && d=1)
Return 1
Else If (a=-1 || b=-1 || c=-1 || d=-1)
Return -1
Else
Return 0
}
Gdip_SetEmptyRegion(Region) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetEmpty", Ptr, Region)
}
Gdip_SetInfiniteRegion(Region) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetInfinite", Ptr, Region)
}
Gdip_GetRegionBounds(pGraphics, Region) {
rData := {}
VarSetCapacity(RectF, 16, 0)
E := DllCall("gdiplus\GdipGetRegionBounds", "UPtr", Region, "UPtr", pGraphics, "UPtr", &RectF)
If (!E) {
rData.x := NumGet(&RectF, 0, "float")
, rData.y := NumGet(&RectF, 4, "float")
, rData.w := NumGet(&RectF, 8, "float")
, rData.h := NumGet(&RectF, 12, "float")
} Else {
Return E
}
return rData
}
Gdip_TranslateRegion(Region, X, Y) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipTranslateRegion", Ptr, Region, "float", X, "float", Y)
}
Gdip_RotateRegionAtCenter(pGraphics, Region, Angle, MatrixOrder:=1) {
Rect := Gdip_GetRegionBounds(pGraphics, Region)
cX := Rect.x + (Rect.w / 2)
cY := Rect.y + (Rect.h / 2)
pMatrix := Gdip_CreateMatrix()
Gdip_TranslateMatrix(pMatrix, -cX , -cY)
Gdip_RotateMatrix(pMatrix, Angle, MatrixOrder)
Gdip_TranslateMatrix(pMatrix, cX, cY, MatrixOrder)
E := Gdip_TransformRegion(Region, pMatrix)
Gdip_DeleteMatrix(pMatrix)
Return E
}
Gdip_TransformRegion(Region, pMatrix) {
return DllCall("gdiplus\GdipTransformRegion", "UPtr", Region, "UPtr", pMatrix)
}
Gdip_CloneRegion(Region) {
newRegion := 0
gdipLastError := DllCall("gdiplus\GdipCloneRegion", "UPtr", Region, "UInt*", newRegion)
return newRegion
}
Gdip_LockBits(pBitmap, x, y, w, h, ByRef Stride, ByRef Scan0, ByRef BitmapData, LockMode := 3, PixelFormat := 0x26200a) {
Static Ptr := "UPtr"
CreateRect(_Rect, x, y, w, h)
VarSetCapacity(BitmapData, 16+2*A_PtrSize, 0)
_E := DllCall("Gdiplus\GdipBitmapLockBits", Ptr, pBitmap, Ptr, &_Rect, "uint", LockMode, "int", PixelFormat, Ptr, &BitmapData)
Stride := NumGet(BitmapData, 8, "Int")
Scan0 := NumGet(BitmapData, 16, Ptr)
return _E
}
Gdip_UnlockBits(pBitmap, ByRef BitmapData) {
Static Ptr := "UPtr"
return DllCall("Gdiplus\GdipBitmapUnlockBits", Ptr, pBitmap, Ptr, &BitmapData)
}
Gdip_SetLockBitPixel(ARGB, Scan0, x, y, Stride) {
NumPut(ARGB, Scan0+0, (x*4)+(y*Stride), "UInt")
}
Gdip_GetLockBitPixel(Scan0, x, y, Stride) {
return NumGet(Scan0+0, (x*4)+(y*Stride), "UInt")
}
Gdip_PixelateBitmap(pBitmap, ByRef pBitmapOut, BlockSize) {
static PixelateBitmap
Static Ptr := "UPtr"
if (!PixelateBitmap)
{
if (A_PtrSize!=8)
MCode_PixelateBitmap := "
      (LTrim Join
      558BEC83EC3C8B4514538B5D1C99F7FB56578BC88955EC894DD885C90F8E830200008B451099F7FB8365DC008365E000894DC88955F08945E833FF897DD4
      397DE80F8E160100008BCB0FAFCB894DCC33C08945F88945FC89451C8945143BD87E608B45088D50028BC82BCA8BF02BF2418945F48B45E02955F4894DC4
      8D0CB80FAFCB03CA895DD08BD1895DE40FB64416030145140FB60201451C8B45C40FB604100145FC8B45F40FB604020145F883C204FF4DE475D6034D18FF
      4DD075C98B4DCC8B451499F7F98945148B451C99F7F989451C8B45FC99F7F98945FC8B45F899F7F98945F885DB7E648B450C8D50028BC82BCA83C103894D
      C48BC82BCA41894DF48B4DD48945E48B45E02955E48D0C880FAFCB03CA895DD08BD18BF38A45148B7DC48804178A451C8B7DF488028A45FC8804178A45F8
      8B7DE488043A83C2044E75DA034D18FF4DD075CE8B4DCC8B7DD447897DD43B7DE80F8CF2FEFFFF837DF0000F842C01000033C08945F88945FC89451C8945
      148945E43BD87E65837DF0007E578B4DDC034DE48B75E80FAF4D180FAFF38B45088D500203CA8D0CB18BF08BF88945F48B45F02BF22BFA2955F48945CC0F
      B6440E030145140FB60101451C0FB6440F010145FC8B45F40FB604010145F883C104FF4DCC75D8FF45E4395DE47C9B8B4DF00FAFCB85C9740B8B451499F7
      F9894514EB048365140033F63BCE740B8B451C99F7F989451CEB0389751C3BCE740B8B45FC99F7F98945FCEB038975FC3BCE740B8B45F899F7F98945F8EB
      038975F88975E43BDE7E5A837DF0007E4C8B4DDC034DE48B75E80FAF4D180FAFF38B450C8D500203CA8D0CB18BF08BF82BF22BFA2BC28B55F08955CC8A55
      1488540E038A551C88118A55FC88540F018A55F888140183C104FF4DCC75DFFF45E4395DE47CA68B45180145E0015DDCFF4DC80F8594FDFFFF8B451099F7
      FB8955F08945E885C00F8E450100008B45EC0FAFC38365DC008945D48B45E88945CC33C08945F88945FC89451C8945148945103945EC7E6085DB7E518B4D
      D88B45080FAFCB034D108D50020FAF4D18034DDC8BF08BF88945F403CA2BF22BFA2955F4895DC80FB6440E030145140FB60101451C0FB6440F010145FC8B
      45F40FB604080145F883C104FF4DC875D8FF45108B45103B45EC7CA08B4DD485C9740B8B451499F7F9894514EB048365140033F63BCE740B8B451C99F7F9
      89451CEB0389751C3BCE740B8B45FC99F7F98945FCEB038975FC3BCE740B8B45F899F7F98945F8EB038975F88975103975EC7E5585DB7E468B4DD88B450C
      0FAFCB034D108D50020FAF4D18034DDC8BF08BF803CA2BF22BFA2BC2895DC88A551488540E038A551C88118A55FC88540F018A55F888140183C104FF4DC8
      75DFFF45108B45103B45EC7CAB8BC3C1E0020145DCFF4DCC0F85CEFEFFFF8B4DEC33C08945F88945FC89451C8945148945103BC87E6C3945F07E5C8B4DD8
      8B75E80FAFCB034D100FAFF30FAF4D188B45088D500203CA8D0CB18BF08BF88945F48B45F02BF22BFA2955F48945C80FB6440E030145140FB60101451C0F
      B6440F010145FC8B45F40FB604010145F883C104FF4DC875D833C0FF45108B4DEC394D107C940FAF4DF03BC874068B451499F7F933F68945143BCE740B8B
      451C99F7F989451CEB0389751C3BCE740B8B45FC99F7F98945FCEB038975FC3BCE740B8B45F899F7F98945F8EB038975F88975083975EC7E63EB0233F639
      75F07E4F8B4DD88B75E80FAFCB034D080FAFF30FAF4D188B450C8D500203CA8D0CB18BF08BF82BF22BFA2BC28B55F08955108A551488540E038A551C8811
      8A55FC88540F018A55F888140883C104FF4D1075DFFF45088B45083B45EC7C9F5F5E33C05BC9C21800
)"
else
MCode_PixelateBitmap := "
      (LTrim Join
      4489442418488954241048894C24085355565741544155415641574883EC28418BC1448B8C24980000004C8BDA99488BD941F7F9448BD0448BFA8954240C
      448994248800000085C00F8E9D020000418BC04533E4458BF299448924244C8954241041F7F933C9898C24980000008BEA89542404448BE889442408EB05
      4C8B5C24784585ED0F8E1A010000458BF1418BFD48897C2418450FAFF14533D233F633ED4533E44533ED4585C97E5B4C63BC2490000000418D040A410FAF
      C148984C8D441802498BD9498BD04D8BD90FB642010FB64AFF4403E80FB60203E90FB64AFE4883C2044403E003F149FFCB75DE4D03C748FFCB75D0488B7C
      24188B8C24980000004C8B5C2478418BC59941F7FE448BE8418BC49941F7FE448BE08BC59941F7FE8BE88BC69941F7FE8BF04585C97E4048639C24900000
      004103CA4D8BC1410FAFC94863C94A8D541902488BCA498BC144886901448821408869FF408871FE4883C10448FFC875E84803D349FFC875DA8B8C249800
      0000488B5C24704C8B5C24784183C20448FFCF48897C24180F850AFFFFFF8B6C2404448B2424448B6C24084C8B74241085ED0F840A01000033FF33DB4533
      DB4533D24533C04585C97E53488B74247085ED7E42438D0C04418BC50FAF8C2490000000410FAFC18D04814863C8488D5431028BCD0FB642014403D00FB6
      024883C2044403D80FB642FB03D80FB642FA03F848FFC975DE41FFC0453BC17CB28BCD410FAFC985C9740A418BC299F7F98BF0EB0233F685C9740B418BC3
      99F7F9448BD8EB034533DB85C9740A8BC399F7F9448BD0EB034533D285C9740A8BC799F7F9448BC0EB034533C033D24585C97E4D4C8B74247885ED7E3841
      8D0C14418BC50FAF8C2490000000410FAFC18D04814863C84A8D4431028BCD40887001448818448850FF448840FE4883C00448FFC975E8FFC2413BD17CBD
      4C8B7424108B8C2498000000038C2490000000488B5C24704503E149FFCE44892424898C24980000004C897424100F859EFDFFFF448B7C240C448B842480
      000000418BC09941F7F98BE8448BEA89942498000000896C240C85C00F8E3B010000448BAC2488000000418BCF448BF5410FAFC9898C248000000033FF33
      ED33F64533DB4533D24533C04585FF7E524585C97E40418BC5410FAFC14103C00FAF84249000000003C74898488D541802498BD90FB642014403D00FB602
      4883C2044403D80FB642FB03F00FB642FA03E848FFCB75DE488B5C247041FFC0453BC77CAE85C9740B418BC299F7F9448BE0EB034533E485C9740A418BC3
      99F7F98BD8EB0233DB85C9740A8BC699F7F9448BD8EB034533DB85C9740A8BC599F7F9448BD0EB034533D24533C04585FF7E4E488B4C24784585C97E3541
      8BC5410FAFC14103C00FAF84249000000003C74898488D540802498BC144886201881A44885AFF448852FE4883C20448FFC875E941FFC0453BC77CBE8B8C
      2480000000488B5C2470418BC1C1E00203F849FFCE0F85ECFEFFFF448BAC24980000008B6C240C448BA4248800000033FF33DB4533DB4533D24533C04585
      FF7E5A488B7424704585ED7E48418BCC8BC5410FAFC94103C80FAF8C2490000000410FAFC18D04814863C8488D543102418BCD0FB642014403D00FB60248
      83C2044403D80FB642FB03D80FB642FA03F848FFC975DE41FFC0453BC77CAB418BCF410FAFCD85C9740A418BC299F7F98BF0EB0233F685C9740B418BC399
      F7F9448BD8EB034533DB85C9740A8BC399F7F9448BD0EB034533D285C9740A8BC799F7F9448BC0EB034533C033D24585FF7E4E4585ED7E42418BCC8BC541
      0FAFC903CA0FAF8C2490000000410FAFC18D04814863C8488B442478488D440102418BCD40887001448818448850FF448840FE4883C00448FFC975E8FFC2
      413BD77CB233C04883C428415F415E415D415C5F5E5D5BC3
)"
VarSetCapacity(PixelateBitmap, StrLen(MCode_PixelateBitmap)//2)
nCount := StrLen(MCode_PixelateBitmap)//2
N := (A_AhkVersion < 2) ? nCount : "nCount"
Loop %N%
NumPut("0x" SubStr(MCode_PixelateBitmap, (2*A_Index)-1, 2), PixelateBitmap, A_Index-1, "UChar")
DllCall("VirtualProtect", Ptr, &PixelateBitmap, Ptr, VarSetCapacity(PixelateBitmap), "uint", 0x40, "UPtr*", 0)
}
Gdip_GetImageDimensions(pBitmap, Width, Height)
if (Width != Gdip_GetImageWidth(pBitmapOut) || Height != Gdip_GetImageHeight(pBitmapOut))
return -1
if (BlockSize > Width || BlockSize > Height)
return -2
E1 := Gdip_LockBits(pBitmap, 0, 0, Width, Height, Stride1, Scan01, BitmapData1)
E2 := Gdip_LockBits(pBitmapOut, 0, 0, Width, Height, Stride2, Scan02, BitmapData2)
if (!E1 && !E2)
DllCall(&PixelateBitmap, Ptr, Scan01, Ptr, Scan02, "int", Width, "int", Height, "int", Stride1, "int", BlockSize)
If !E1
Gdip_UnlockBits(pBitmap, BitmapData1)
If !E2
Gdip_UnlockBits(pBitmapOut, BitmapData2)
return 0
}
Gdip_ToARGB(A, R, G, B) {
return (A << 24) | (R << 16) | (G << 8) | B
}
Gdip_FromARGB(ARGB, ByRef A, ByRef R, ByRef G, ByRef B) {
A := (0xff000000 & ARGB) >> 24
R := (0x00ff0000 & ARGB) >> 16
G := (0x0000ff00 & ARGB) >> 8
B := 0x000000ff & ARGB
}
Gdip_AFromARGB(ARGB) {
return (0xff000000 & ARGB) >> 24
}
Gdip_RFromARGB(ARGB) {
return (0x00ff0000 & ARGB) >> 16
}
Gdip_GFromARGB(ARGB) {
return (0x0000ff00 & ARGB) >> 8
}
Gdip_BFromARGB(ARGB) {
return 0x000000ff & ARGB
}
StrGetB(Address, Length:=-1, Encoding:=0) {
if !IsInteger(Length)
Encoding := Length,  Length := -1
if (Address+0 < 1024)
return
if (Encoding = "UTF-16")
Encoding := 1200
else if (Encoding = "UTF-8")
Encoding := 65001
else if SubStr(Encoding,1,2)="CP"
Encoding := SubStr(Encoding,3)
if !Encoding
{
if (Length == -1)
Length := DllCall("lstrlen", "uint", Address)
VarSetCapacity(String, Length)
DllCall("lstrcpyn", "str", String, "uint", Address, "int", Length + 1)
}
else if (Encoding = 1200)
{
char_count := DllCall("WideCharToMultiByte", "uint", 0, "uint", 0x400, "uint", Address, "int", Length, "uint", 0, "uint", 0, "uint", 0, "uint", 0)
VarSetCapacity(String, char_count)
DllCall("WideCharToMultiByte", "uint", 0, "uint", 0x400, "uint", Address, "int", Length, "str", String, "int", char_count, "uint", 0, "uint", 0)
}
else if IsInteger(Encoding)
{
char_count := DllCall("MultiByteToWideChar", "uint", Encoding, "uint", 0, "uint", Address, "int", Length, "uint", 0, "int", 0)
VarSetCapacity(String, char_count * 2)
char_count := DllCall("MultiByteToWideChar", "uint", Encoding, "uint", 0, "uint", Address, "int", Length, "uint", &String, "int", char_count * 2)
String := StrGetB(&String, char_count, 1200)
}
return String
}
Gdip_Startup(multipleInstances:=0) {
Static Ptr := "UPtr"
pToken := 0
If (multipleInstances=0)
{
if !DllCall("GetModuleHandle", "str", "gdiplus", Ptr)
DllCall("LoadLibrary", "str", "gdiplus")
} Else DllCall("LoadLibrary", "str", "gdiplus")
VarSetCapacity(si, A_PtrSize = 8 ? 24 : 16, 0), si := Chr(1)
DllCall("gdiplus\GdiplusStartup", "UPtr*", pToken, Ptr, &si, Ptr, 0)
return pToken
}
Gdip_Shutdown(pToken) {
Static Ptr := "UPtr"
DllCall("gdiplus\GdiplusShutdown", Ptr, pToken)
hModule := DllCall("GetModuleHandle", "str", "gdiplus", Ptr)
if hModule
DllCall("FreeLibrary", Ptr, hModule)
return 0
}
IsInteger(Var) {
Static Integer := "Integer"
If Var Is Integer
Return True
Return False
}
IsNumber(Var) {
Static number := "number"
If Var Is number
Return True
Return False
}
GetMonitorCount() {
Monitors := MDMF_Enum()
for k,v in Monitors
count := A_Index
return count
}
GetMonitorInfo(MonitorNum) {
Monitors := MDMF_Enum()
for k,v in Monitors
if (v.Num = MonitorNum)
return v
}
GetPrimaryMonitor() {
Monitors := MDMF_Enum()
for k,v in Monitors
If (v.Primary)
return v.Num
}
MDMF_Enum(HMON := "") {
Static CallbackFunc := Func(A_AhkVersion < "2" ? "RegisterCallback" : "CallbackCreate")
Static EnumProc := CallbackFunc.Call("MDMF_EnumProc")
Static Obj := (A_AhkVersion < "2") ? "Object" : "Map"
Static Monitors := {}
If (HMON = "")
{
Monitors := %Obj%("TotalCount", 0)
If !DllCall("User32.dll\EnumDisplayMonitors", "Ptr", 0, "Ptr", 0, "Ptr", EnumProc, "Ptr", &Monitors, "Int")
Return False
}
Return (HMON = "") ? Monitors : Monitors.HasKey(HMON) ? Monitors[HMON] : False
}
MDMF_EnumProc(HMON, HDC, PRECT, ObjectAddr) {
Monitors := Object(ObjectAddr)
Monitors[HMON] := MDMF_GetInfo(HMON)
Monitors["TotalCount"]++
If (Monitors[HMON].Primary)
Monitors["Primary"] := HMON
Return True
}
MDMF_FromHWND(HWND, Flag := 0) {
Return DllCall("User32.dll\MonitorFromWindow", "Ptr", HWND, "UInt", Flag, "Ptr")
}
MDMF_FromPoint(ByRef X := "", ByRef Y := "", Flag := 0) {
If (X = "") || (Y = "") {
VarSetCapacity(PT, 8, 0)
DllCall("User32.dll\GetCursorPos", "Ptr", &PT, "Int")
If (X = "")
X := NumGet(PT, 0, "Int")
If (Y = "")
Y := NumGet(PT, 4, "Int")
}
Return DllCall("User32.dll\MonitorFromPoint", "Int64", (X & 0xFFFFFFFF) | (Y << 32), "UInt", Flag, "Ptr")
}
MDMF_FromRect(X, Y, W, H, Flag := 0) {
VarSetCapacity(RC, 16, 0)
NumPut(X, RC, 0, "Int"), NumPut(Y, RC, 4, "Int"), NumPut(X + W, RC, 8, "Int"), NumPut(Y + H, RC, 12, "Int")
Return DllCall("User32.dll\MonitorFromRect", "Ptr", &RC, "UInt", Flag, "Ptr")
}
MDMF_GetInfo(HMON) {
NumPut(VarSetCapacity(MIEX, 40 + (32 << !!A_IsUnicode)), MIEX, 0, "UInt")
If DllCall("User32.dll\GetMonitorInfo", "Ptr", HMON, "Ptr", &MIEX, "Int")
Return {Name:      (Name := StrGet(&MIEX + 40, 32))
, Num:       RegExReplace(Name, ".*(\d+)$", "$1")
, Left:      NumGet(MIEX, 4, "Int")
, Top:       NumGet(MIEX, 8, "Int")
, Right:     NumGet(MIEX, 12, "Int")
, Bottom:    NumGet(MIEX, 16, "Int")
, WALeft:    NumGet(MIEX, 20, "Int")
, WATop:     NumGet(MIEX, 24, "Int")
, WARight:   NumGet(MIEX, 28, "Int")
, WABottom:  NumGet(MIEX, 32, "Int")
, Primary:   NumGet(MIEX, 36, "UInt")}
Return False
}
Gdip_LoadImageFromFile(sFile, useICM:=0) {
pImage := 0
function2call := (useICM=1) ? "ICM" : ""
gdipLastError := DllCall("gdiplus\GdipLoadImageFromFile" function2call, "WStr", sFile, "UPtrP", pImage)
Return pImage
}
Gdip_GetPropertyCount(pImage) {
PropCount := 0
Static Ptr := "UPtr"
R := DllCall("gdiplus\GdipGetPropertyCount", Ptr, pImage, "UIntP", PropCount)
ErrorLevel := R
Return PropCount
}
Gdip_GetPropertyIdList(pImage) {
PropNum := Gdip_GetPropertyCount(pImage)
Static Ptr := "UPtr"
If (ErrorLevel) || (PropNum = 0)
Return False
VarSetCapacity(PropIDList, 4 * PropNum, 0)
R := DllCall("gdiplus\GdipGetPropertyIdList", Ptr, pImage, "UInt", PropNum, "Ptr", &PropIDList)
If (R) {
ErrorLevel := R
Return False
}
PropArray := {Count: PropNum}
Loop %PropNum%
{
PropID := NumGet(PropIDList, (A_Index - 1) << 2, "UInt")
PropArray[PropID] := Gdip_GetPropertyTagName(PropID)
}
Return PropArray
}
Gdip_GetPropertyItem(pImage, PropID) {
PropItem := {Length: 0, Type: 0, Value: ""}
ItemSize := 0
R := DllCall("gdiplus\GdipGetPropertyItemSize", "Ptr", pImage, "UInt", PropID, "UIntP", ItemSize)
If (R) {
ErrorLevel := R
Return False
}
Static Ptr := "UPtr"
VarSetCapacity(Item, ItemSize, 0)
R := DllCall("gdiplus\GdipGetPropertyItem", Ptr, pImage, "UInt", PropID, "UInt", ItemSize, "Ptr", &Item)
If (R) {
ErrorLevel := R
Return False
}
PropLen := NumGet(Item, 4, "UInt")
PropType := NumGet(Item, 8, "Short")
PropAddr := NumGet(Item, 8 + A_PtrSize, "UPtr")
PropItem.Length := PropLen
PropItem.Type := PropType
If (PropLen > 0)
{
PropVal := ""
Gdip_GetPropertyItemValue(PropVal, PropLen, PropType, PropAddr)
If (PropType = 1) || (PropType = 7) {
PropItem.SetCapacity("Value", PropLen)
ValAddr := PropItem.GetAddress("Value")
DllCall("Kernel32.dll\RtlMoveMemory", "Ptr", ValAddr, "Ptr", &PropVal, "Ptr", PropLen)
} Else {
PropItem.Value := PropVal
}
}
ErrorLevel := 0
Return PropItem
}
Gdip_GetAllPropertyItems(pImage) {
BufSize := PropNum := ErrorLevel := 0
R := DllCall("gdiplus\GdipGetPropertySize", "Ptr", pImage, "UIntP", BufSize, "UIntP", PropNum)
If (R) || (PropNum = 0) {
ErrorLevel := R ? R : 19
Return False
}
VarSetCapacity(Buffer, BufSize, 0)
Static Ptr := "UPtr"
R := DllCall("gdiplus\GdipGetAllPropertyItems", Ptr, pImage, "UInt", BufSize, "UInt", PropNum, "Ptr", &Buffer)
If (R) {
ErrorLevel := R
Return False
}
PropsObj := {Count: PropNum}
PropSize := 8 + (2 * A_PtrSize)
Loop %PropNum%
{
OffSet := PropSize * (A_Index - 1)
PropID := NumGet(Buffer, OffSet, "UInt")
PropLen := NumGet(Buffer, OffSet + 4, "UInt")
PropType := NumGet(Buffer, OffSet + 8, "Short")
PropAddr := NumGet(Buffer, OffSet + 8 + A_PtrSize, "UPtr")
PropVal := ""
PropsObj[PropID] := {}
PropsObj[PropID, "Length"] := PropLen
PropsObj[PropID, "Type"] := PropType
PropsObj[PropID, "Value"] := PropVal
If (PropLen > 0)
{
Gdip_GetPropertyItemValue(PropVal, PropLen, PropType, PropAddr)
If (PropType = 1) || (PropType = 7)
{
PropsObj[PropID].SetCapacity("Value", PropLen)
ValAddr := PropsObj[PropID].GetAddress("Value")
DllCall("Kernel32.dll\RtlMoveMemory", "Ptr", ValAddr, "Ptr", PropAddr, "Ptr", PropLen)
} Else {
PropsObj[PropID].Value := PropVal
}
}
}
ErrorLevel := 0
Return PropsObj
}
Gdip_GetPropertyTagName(PropID) {
Static PropTagsA := {0x0001:"GPS LatitudeRef",0x0002:"GPS Latitude",0x0003:"GPS LongitudeRef",0x0004:"GPS Longitude",0x0005:"GPS AltitudeRef",0x0006:"GPS Altitude",0x0007:"GPS Time",0x0008:"GPS Satellites",0x0009:"GPS Status",0x000A:"GPS MeasureMode",0x001D:"GPS Date",0x001E:"GPS Differential",0x00FE:"NewSubfileType",0x00FF:"SubfileType",0x0102:"Bits Per Sample",0x0103:"Compression",0x0106:"Photometric Interpolation",0x0107:"ThreshHolding",0x010A:"Fill Order",0x010D:"Document Name",0x010E:"Image Description",0x010F:"Equipment Make",0x0110:"Equipment Model",0x0112:"Orientation",0x0115:"Samples Per Pixel",0x0118:"Min Sample Value",0x0119:"Max Sample Value",0x011D:"Page Name",0x0122:"GrayResponseUnit",0x0123:"GrayResponseCurve",0x0128:"Resolution Unit",0x012D:"Transfer Function",0x0131:"Software Used",0x0132:"Internal Date Time",0x013B:"Artist"
,0x013C:"Host Computer",0x013D:"Predictor",0x013E:"White Point",0x013F:"Primary Chromaticities",0x0140:"Color Map",0x014C:"Ink Set",0x014D:"Ink Names",0x014E:"Number Of Inks",0x0150:"Dot Range",0x0151:"Target Printer",0x0152:"Extra Samples",0x0153:"Sample Format",0x0156:"Transfer Range",0x0200:"JPEGProc",0x0205:"JPEGLosslessPredictors",0x0301:"Gamma",0x0302:"ICC Profile Descriptor",0x0303:"SRGB Rendering Intent",0x0320:"Image Title",0x5010:"JPEG Quality",0x5011:"Grid Size",0x501A:"Color Transfer Function",0x5100:"Frame Delay",0x5101:"Loop Count",0x5110:"Pixel Unit",0x5111:"Pixel Per Unit X",0x5112:"Pixel Per Unit Y",0x8298:"Copyright",0x829A:"EXIF Exposure Time",0x829D:"EXIF F Number",0x8773:"ICC Profile",0x8822:"EXIF ExposureProg",0x8824:"EXIF SpectralSense",0x8827:"EXIF ISO Speed",0x9003:"EXIF Date Original",0x9004:"EXIF Date Digitized"
,0x9102:"EXIF CompBPP",0x9201:"EXIF Shutter Speed",0x9202:"EXIF Aperture",0x9203:"EXIF Brightness",0x9204:"EXIF Exposure Bias",0x9205:"EXIF Max. Aperture",0x9206:"EXIF Subject Dist",0x9207:"EXIF Metering Mode",0x9208:"EXIF Light Source",0x9209:"EXIF Flash",0x920A:"EXIF Focal Length",0x9214:"EXIF Subject Area",0x927C:"EXIF Maker Note",0x9286:"EXIF Comments",0xA001:"EXIF Color Space",0xA002:"EXIF PixXDim",0xA003:"EXIF PixYDim",0xA004:"EXIF Related WAV",0xA005:"EXIF Interop",0xA20B:"EXIF Flash Energy",0xA20E:"EXIF Focal X Res",0xA20F:"EXIF Focal Y Res",0xA210:"EXIF FocalResUnit",0xA214:"EXIF Subject Loc",0xA215:"EXIF Exposure Index",0xA217:"EXIF Sensing Method",0xA300:"EXIF File Source",0xA301:"EXIF Scene Type",0xA401:"EXIF Custom Rendered",0xA402:"EXIF Exposure Mode",0xA403:"EXIF White Balance",0xA404:"EXIF Digital Zoom Ratio"
,0xA405:"EXIF Focal Length In 35mm Film",0xA406:"EXIF Scene Capture Type",0xA407:"EXIF Gain Control",0xA408:"EXIF Contrast",0xA409:"EXIF Saturation",0xA40A:"EXIF Sharpness",0xA40B:"EXIF Device Setting Description",0xA40C:"EXIF Subject Distance Range",0xA420:"EXIF Unique Image ID"}
Static PropTagsB := {0x0000:"GpsVer",0x000B:"GpsGpsDop",0x000C:"GpsSpeedRef",0x000D:"GpsSpeed",0x000E:"GpsTrackRef",0x000F:"GpsTrack",0x0010:"GpsImgDirRef",0x0011:"GpsImgDir",0x0012:"GpsMapDatum",0x0013:"GpsDestLatRef",0x0014:"GpsDestLat",0x0015:"GpsDestLongRef",0x0016:"GpsDestLong",0x0017:"GpsDestBearRef",0x0018:"GpsDestBear",0x0019:"GpsDestDistRef",0x001A:"GpsDestDist",0x001B:"GpsProcessingMethod",0x001C:"GpsAreaInformation",0x0100:"Original Image Width",0x0101:"Original Image Height",0x0108:"CellWidth",0x0109:"CellHeight",0x0111:"Strip Offsets",0x0116:"RowsPerStrip",0x0117:"StripBytesCount",0x011A:"XResolution",0x011B:"YResolution",0x011C:"Planar Config",0x011E:"XPosition",0x011F:"YPosition",0x0120:"FreeOffset",0x0121:"FreeByteCounts",0x0124:"T4Option",0x0125:"T6Option",0x0129:"PageNumber",0x0141:"Halftone Hints",0x0142:"TileWidth",0x0143:"TileLength",0x0144:"TileOffset"
,0x0145:"TileByteCounts",0x0154:"SMin Sample Value",0x0155:"SMax Sample Value",0x0201:"JPEGInterFormat",0x0202:"JPEGInterLength",0x0203:"JPEGRestartInterval",0x0206:"JPEGPointTransforms",0x0207:"JPEGQTables",0x0208:"JPEGDCTables",0x0209:"JPEGACTables",0x0211:"YCbCrCoefficients",0x0212:"YCbCrSubsampling",0x0213:"YCbCrPositioning",0x0214:"REFBlackWhite",0x5001:"ResolutionXUnit",0x5002:"ResolutionYUnit",0x5003:"ResolutionXLengthUnit",0x5004:"ResolutionYLengthUnit",0x5005:"PrintFlags",0x5006:"PrintFlagsVersion",0x5007:"PrintFlagsCrop",0x5008:"PrintFlagsBleedWidth",0x5009:"PrintFlagsBleedWidthScale",0x500A:"HalftoneLPI",0x500B:"HalftoneLPIUnit",0x500C:"HalftoneDegree",0x500D:"HalftoneShape",0x500E:"HalftoneMisc",0x500F:"HalftoneScreen",0x5012:"ThumbnailFormat",0x5013:"ThumbnailWidth",0x5014:"ThumbnailHeight",0x5015:"ThumbnailColorDepth"
,0x5016:"ThumbnailPlanes",0x5017:"ThumbnailRawBytes",0x5018:"ThumbnailSize",0x5019:"ThumbnailCompressedSize",0x501B:"ThumbnailData",0x5020:"ThumbnailImageWidth",0x5021:"ThumbnailImageHeight",0x5022:"ThumbnailBitsPerSample",0x5023:"ThumbnailCompression",0x5024:"ThumbnailPhotometricInterp",0x5025:"ThumbnailImageDescription",0x5026:"ThumbnailEquipMake",0x5027:"ThumbnailEquipModel",0x5028:"ThumbnailStripOffsets",0x5029:"ThumbnailOrientation",0x502A:"ThumbnailSamplesPerPixel",0x502B:"ThumbnailRowsPerStrip",0x502C:"ThumbnailStripBytesCount",0x502D:"ThumbnailResolutionX",0x502E:"ThumbnailResolutionY",0x502F:"ThumbnailPlanarConfig",0x5030:"ThumbnailResolutionUnit",0x5031:"ThumbnailTransferFunction",0x5032:"ThumbnailSoftwareUsed",0x5033:"ThumbnailDateTime",0x5034:"ThumbnailArtist",0x5035:"ThumbnailWhitePoint"
,0x5036:"ThumbnailPrimaryChromaticities",0x5037:"ThumbnailYCbCrCoefficients",0x5038:"ThumbnailYCbCrSubsampling",0x5039:"ThumbnailYCbCrPositioning",0x503A:"ThumbnailRefBlackWhite",0x503B:"ThumbnailCopyRight",0x5090:"LuminanceTable",0x5091:"ChrominanceTable",0x5102:"Global Palette",0x5103:"Index Background",0x5104:"Index Transparent",0x5113:"Palette Histogram",0x8769:"ExifIFD",0x8825:"GpsIFD",0x8828:"ExifOECF",0x9000:"ExifVer",0x9101:"EXIF CompConfig",0x9290:"EXIF DTSubsec",0x9291:"EXIF DTOrigSS",0x9292:"EXIF DTDigSS",0xA000:"EXIF FPXVer",0xA20C:"EXIF Spatial FR",0xA302:"EXIF CfaPattern"}
r := PropTagsA.HasKey(PropID) ? PropTagsA[PropID] : "Unknown"
If (r="Unknown")
r := PropTagsB.HasKey(PropID) ? PropTagsB[PropID] : "Unknown"
Return r
}
Gdip_GetPropertyTagType(PropType) {
Static PropTypes := {1: "Byte", 2: "ASCII", 3: "Short", 4: "Long", 5: "Rational", 7: "Undefined", 9: "SLong", 10: "SRational"}
Return PropTypes.HasKey(PropType) ? PropTypes[PropType] : "Unknown"
}
Gdip_GetPropertyItemValue(ByRef PropVal, PropLen, PropType, PropAddr) {
PropVal := ""
If (PropType = 2)
{
PropVal := StrGet(PropAddr, PropLen, "CP0")
Return True
}
If (PropType = 3)
{
PropyLen := PropLen // 2
Loop %PropyLen%
PropVal .= (A_Index > 1 ? " " : "") . NumGet(PropAddr + 0, (A_Index - 1) << 1, "Short")
Return True
}
If (PropType = 4) || (PropType = 9)
{
NumType := PropType = 4 ? "UInt" : "Int"
PropyLen := PropLen // 4
Loop %PropyLen%
PropVal .= (A_Index > 1 ? " " : "") . NumGet(PropAddr + 0, (A_Index - 1) << 2, NumType)
Return True
}
If (PropType = 5) || (PropType = 10)
{
NumType := PropType = 5 ? "UInt" : "Int"
PropyLen := PropLen // 8
Loop %PropyLen%
PropVal .= (A_Index > 1 ? " " : "") . NumGet(PropAddr + 0, (A_Index - 1) << 2, NumType)
.  "/" . NumGet(PropAddr + 4, (A_Index - 1) << 2, NumType)
Return True
}
If (PropType = 1) || (PropType = 7)
{
VarSetCapacity(PropVal, PropLen, 0)
DllCall("Kernel32.dll\RtlMoveMemory", "Ptr", &PropVal, "Ptr", PropAddr, "Ptr", PropLen)
Return True
}
Return False
}
Gdip_RotatePathAtCenter(pPath, Angle, MatrixOrder:=1, withinBounds:=0, withinBkeepRatio:=1) {
Rect := Gdip_GetPathWorldBounds(pPath)
cX := Rect.x + (Rect.w / 2)
cY := Rect.y + (Rect.h / 2)
pMatrix := Gdip_CreateMatrix()
Gdip_TranslateMatrix(pMatrix, -cX , -cY)
Gdip_RotateMatrix(pMatrix, Angle, MatrixOrder)
Gdip_TranslateMatrix(pMatrix, cX, cY, MatrixOrder)
E := Gdip_TransformPath(pPath, pMatrix)
Gdip_DeleteMatrix(pMatrix)
If (withinBounds=1 && !E && Angle!=0)
{
nRect := Gdip_GetPathWorldBounds(pPath)
ncX := nRect.x + (nRect.w / 2)
ncY := nRect.y + (nRect.h / 2)
pMatrix := Gdip_CreateMatrix()
Gdip_TranslateMatrix(pMatrix, -ncX , -ncY)
sX := Rect.w / nRect.w
sY := Rect.h / nRect.h
If (withinBkeepRatio=1)
{
sX := min(sX, sY)
sY := min(sX, sY)
}
Gdip_ScaleMatrix(pMatrix, sX, sY, MatrixOrder)
Gdip_TranslateMatrix(pMatrix, ncX, ncY, MatrixOrder)
If (sX!=0 && sY!=0)
E := Gdip_TransformPath(pPath, pMatrix)
Gdip_DeleteMatrix(pMatrix)
}
Return E
}
Gdip_ResetMatrix(hMatrix) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipResetMatrix", Ptr, hMatrix)
}
Gdip_RotateMatrix(hMatrix, Angle, MatrixOrder:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipRotateMatrix", Ptr, hMatrix, "float", Angle, "Int", MatrixOrder)
}
Gdip_GetPathWorldBounds(pPath, hMatrix:=0, pPen:=0) {
rData := {}
VarSetCapacity(RectF, 16, 0)
E := DllCall("gdiplus\GdipGetPathWorldBounds", "UPtr", pPath, "UPtr", &RectF, "UPtr", hMatrix, "UPtr", pPen)
If (!E) {
rData.x := NumGet(&RectF, 0, "float")
, rData.y := NumGet(&RectF, 4, "float")
, rData.w := NumGet(&RectF, 8, "float")
, rData.h := NumGet(&RectF, 12, "float")
} Else {
Return E
}
return rData
}
Gdip_ScaleMatrix(hMatrix, ScaleX, ScaleY, MatrixOrder:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipScaleMatrix", Ptr, hMatrix, "float", ScaleX, "float", ScaleY, "Int", MatrixOrder)
}
Gdip_TranslateMatrix(hMatrix, offsetX, offsetY, MatrixOrder:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipTranslateMatrix", Ptr, hMatrix, "float", offsetX, "float", offsetY, "Int", MatrixOrder)
}
Gdip_TransformPath(pPath, hMatrix) {
return DllCall("gdiplus\GdipTransformPath", "UPtr", pPath, "UPtr", hMatrix)
}
Gdip_SetMatrixElements(hMatrix, m11, m12, m21, m22, x, y) {
return DllCall("gdiplus\GdipSetMatrixElements", "UPtr", hMatrix, "float", m11, "float", m12, "float", m21, "float", m22, "float", x, "float", y)
}
Gdip_GetMatrixLastStatus(pMatrix) {
return DllCall("gdiplus\GdipGetLastStatus", "UPtr", pMatrix)
}
Gdip_AddPathBeziers(pPath, Points) {
iCount := CreatePointsF(PointsF, Points)
return DllCall("gdiplus\GdipAddPathBeziers", "UPtr", pPath, "UPtr", &PointsF, "int", iCount)
}
Gdip_AddPathBezier(pPath, x1, y1, x2, y2, x3, y3, x4, y4) {
return DllCall("gdiplus\GdipAddPathBezier", "UPtr", pPath
, "float", x1, "float", y1, "float", x2, "float", y2
, "float", x3, "float", y3, "float", x4, "float", y4)
}
Gdip_AddPathLines(pPath, Points) {
iCount := CreatePointsF(PointsF, Points)
return DllCall("gdiplus\GdipAddPathLine2", "UPtr", pPath, "UPtr", &PointsF, "int", iCount)
}
Gdip_AddPathLine(pPath, x1, y1, x2, y2) {
return DllCall("gdiplus\GdipAddPathLine", "UPtr", pPath, "float", x1, "float", y1, "float", x2, "float", y2)
}
Gdip_AddPathArc(pPath, x, y, w, h, StartAngle, SweepAngle) {
return DllCall("gdiplus\GdipAddPathArc", "UPtr", pPath, "float", x, "float", y, "float", w, "float", h, "float", StartAngle, "float", SweepAngle)
}
Gdip_AddPathPie(pPath, x, y, w, h, StartAngle, SweepAngle) {
return DllCall("gdiplus\GdipAddPathPie", "UPtr", pPath, "float", x, "float", y, "float", w, "float", h, "float", StartAngle, "float", SweepAngle)
}
Gdip_StartPathFigure(pPath) {
return DllCall("gdiplus\GdipStartPathFigure", "UPtr", pPath)
}
Gdip_ClosePathFigure(pPath) {
return DllCall("gdiplus\GdipClosePathFigure", "UPtr", pPath)
}
Gdip_ClosePathFigures(pPath) {
return DllCall("gdiplus\GdipClosePathFigures", "UPtr", pPath)
}
Gdip_DrawPath(pGraphics, pPen, pPath) {
Return DllCall("gdiplus\GdipDrawPath", "UPtr", pGraphics, "UPtr", pPen, "UPtr", pPath)
}
Gdip_ClonePath(pPath) {
pPathClone := 0
gdipLastError := DllCall("gdiplus\GdipClonePath", "UPtr", pPath, "UPtr*", pPathClone)
return pPathClone
}
Gdip_PathGradientCreateFromPath(pPath) {
pBrush := 0
gdipLastError := DllCall("gdiplus\GdipCreatePathGradientFromPath", "Ptr", pPath, "PtrP", pBrush)
Return pBrush
}
Gdip_PathGradientSetCenterPoint(pBrush, X, Y) {
VarSetCapacity(POINTF, 8)
NumPut(X, POINTF, 0, "Float")
NumPut(Y, POINTF, 4, "Float")
Return DllCall("gdiplus\GdipSetPathGradientCenterPoint", "UPtr", pBrush, "Ptr", &POINTF)
}
Gdip_PathGradientSetCenterColor(pBrush, CenterColor) {
Return DllCall("gdiplus\GdipSetPathGradientCenterColor", "UPtr", pBrush, "UInt", CenterColor)
}
Gdip_PathGradientSetSurroundColors(pBrush, SurroundColors) {
Colors := StrSplit(SurroundColors, "|")
tColors := Colors.Length()
VarSetCapacity(ColorArray, 4 * tColors, 0)
Loop %tColors% {
NumPut(Colors[A_Index], ColorArray, 4 * (A_Index - 1), "UInt")
}
Return DllCall("gdiplus\GdipSetPathGradientSurroundColorsWithCount", "Ptr", pBrush, "Ptr", &ColorArray
, "IntP", tColors)
}
Gdip_PathGradientSetSigmaBlend(pBrush, Focus, Scale:=1) {
Return DllCall("gdiplus\GdipSetPathGradientSigmaBlend", "Ptr", pBrush, "Float", Focus, "Float", Scale)
}
Gdip_PathGradientSetLinearBlend(pBrush, Focus, Scale:=1) {
Return DllCall("gdiplus\GdipSetPathGradientLinearBlend", "Ptr", pBrush, "Float", Focus, "Float", Scale)
}
Gdip_PathGradientSetFocusScales(pBrush, xScale, yScale) {
Return DllCall("gdiplus\GdipSetPathGradientFocusScales", "Ptr", pBrush, "Float", xScale, "Float", yScale)
}
Gdip_AddPathGradient(pGraphics, x, y, w, h, cX, cY, cClr, sClr, BlendFocus, ScaleX, ScaleY, Shape, Angle:=0) {
pPath := Gdip_CreatePath()
If (Shape=1)
Gdip_AddPathRectangle(pPath, x, y, W, H)
Else
Gdip_AddPathEllipse(pPath, x, y, W, H)
zBrush := Gdip_PathGradientCreateFromPath(pPath)
If (Angle!=0)
Gdip_RotatePathGradientAtCenter(zBrush, Angle)
Gdip_PathGradientSetCenterPoint(zBrush, cX, cY)
Gdip_PathGradientSetCenterColor(zBrush, cClr)
Gdip_PathGradientSetSurroundColors(zBrush, sClr)
Gdip_PathGradientSetSigmaBlend(zBrush, BlendFocus)
Gdip_PathGradientSetLinearBlend(zBrush, BlendFocus)
Gdip_PathGradientSetFocusScales(zBrush, ScaleX, ScaleY)
E := Gdip_FillPath(pGraphics, zBrush, pPath)
Gdip_DeleteBrush(zBrush)
Gdip_DeletePath(pPath)
Return E
}
Gdip_CreatePathGradient(Points, WrapMode) {
Static Ptr := "UPtr"
iCount := CreatePointsF(PointsF, Points)
pPathGradientBrush := 0
gdipLastError := DllCall("gdiplus\GdipCreatePathGradient", Ptr, &PointsF, "int", iCount, "int", WrapMode, "int*", pPathGradientBrush)
Return pPathGradientBrush
}
Gdip_PathGradientGetGammaCorrection(pPathGradientBrush) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetPathGradientGammaCorrection", Ptr, pPathGradientBrush, "int*", result)
If E
return -1
Return result
}
Gdip_PathGradientGetPointCount(pPathGradientBrush) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetPathGradientPointCount", Ptr, pPathGradientBrush, "int*", result)
If E
return -1
Return result
}
Gdip_PathGradientGetWrapMode(pPathGradientBrush) {
result := 0
E := DllCall("gdiplus\GdipGetPathGradientWrapMode", "UPtr", pPathGradientBrush, "int*", result)
If E
return -1
Return result
}
Gdip_PathGradientGetRect(pPathGradientBrush) {
rData := {}
VarSetCapacity(RectF, 16, 0)
E := DllCall("gdiplus\GdipGetPathGradientRect", "UPtr", pPathGradientBrush, "UPtr", &RectF)
If (!E) {
rData.x := NumGet(&RectF, 0, "float")
, rData.y := NumGet(&RectF, 4, "float")
, rData.w := NumGet(&RectF, 8, "float")
, rData.h := NumGet(&RectF, 12, "float")
} Else {
Return E
}
return rData
}
Gdip_PathGradientResetTransform(pPathGradientBrush) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipResetPathGradientTransform", Ptr, pPathGradientBrush)
}
Gdip_PathGradientRotateTransform(pPathGradientBrush, Angle, matrixOrder:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipRotatePathGradientTransform", Ptr, pPathGradientBrush, "float", Angle, "int", matrixOrder)
}
Gdip_PathGradientScaleTransform(pPathGradientBrush, ScaleX, ScaleY, matrixOrder:=0) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipScalePathGradientTransform", Ptr, pPathGradientBrush, "float", ScaleX, "float", ScaleY, "int", matrixOrder)
}
Gdip_PathGradientTranslateTransform(pPathGradientBrush, X, Y, matrixOrder:=0) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipTranslatePathGradientTransform", Ptr, pPathGradientBrush, "float", X, "float", Y, "int", matrixOrder)
}
Gdip_PathGradientMultiplyTransform(pPathGradientBrush, hMatrix, matrixOrder:=0) {
Static Ptr := "UPtr"
Return DllCall("gdiplus\GdipMultiplyPathGradientTransform", Ptr, pPathGradientBrush, Ptr, hMatrix, "int", matrixOrder)
}
Gdip_PathGradientSetTransform(pPathGradientBrush, pMatrix) {
return DllCall("gdiplus\GdipSetPathGradientTransform", "UPtr", pPathGradientBrush, "UPtr", pMatrix)
}
Gdip_PathGradientGetTransform(pPathGradientBrush) {
pMatrix := 0
gdipLastError := DllCall("gdiplus\GdipGetPathGradientTransform", "UPtr", pPathGradientBrush, "UPtr*", pMatrix)
Return pMatrix
}
Gdip_RotatePathGradientAtCenter(pPathGradientBrush, Angle, MatrixOrder:=1) {
Rect := Gdip_PathGradientGetRect(pPathGradientBrush)
cX := Rect.x + (Rect.w / 2)
cY := Rect.y + (Rect.h / 2)
pMatrix := Gdip_CreateMatrix()
Gdip_TranslateMatrix(pMatrix, -cX , -cY)
Gdip_RotateMatrix(pMatrix, Angle, MatrixOrder)
Gdip_TranslateMatrix(pMatrix, cX, cY, MatrixOrder)
E := Gdip_PathGradientSetTransform(pPathGradientBrush, pMatrix)
Gdip_DeleteMatrix(pMatrix)
Return E
}
Gdip_PathGradientSetGammaCorrection(pPathGradientBrush, UseGammaCorrection) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetPathGradientGammaCorrection", Ptr, pPathGradientBrush, "int", UseGammaCorrection)
}
Gdip_PathGradientSetWrapMode(pPathGradientBrush, WrapMode) {
Static Ptr := "UPtr"
return DllCall("gdiplus\GdipSetPathGradientWrapMode", Ptr, pPathGradientBrush, "int", WrapMode)
}
Gdip_PathGradientGetCenterColor(pPathGradientBrush) {
Static Ptr := "UPtr"
ARGB := 0
E := DllCall("gdiplus\GdipGetPathGradientCenterColor", Ptr, pPathGradientBrush, "uint*", ARGB)
If E
return -1
Return Format("{1:#x}", ARGB)
}
Gdip_PathGradientGetCenterPoint(pPathGradientBrush, ByRef X, ByRef Y) {
Static Ptr := "UPtr"
VarSetCapacity(PointF, 8, 0)
E := DllCall("gdiplus\GdipGetPathGradientCenterPoint", Ptr, pPathGradientBrush, "UPtr", &PointF)
If !E
{
x := NumGet(PointF, 0, "float")
y := NumGet(PointF, 4, "float")
}
Return E
}
Gdip_PathGradientGetFocusScales(pPathGradientBrush, ByRef X, ByRef Y) {
Static Ptr := "UPtr"
x := 0
y := 0
Return DllCall("gdiplus\GdipGetPathGradientFocusScales", Ptr, pPathGradientBrush, "float*", X, "float*", Y)
}
Gdip_PathGradientGetSurroundColorCount(pPathGradientBrush) {
Static Ptr := "UPtr"
result := 0
E := DllCall("gdiplus\GdipGetPathGradientSurroundColorCount", Ptr, pPathGradientBrush, "int*", result)
If E
return -1
Return result
}
Gdip_GetPathGradientSurroundColors(pPathGradientBrush) {
iCount := Gdip_PathGradientGetSurroundColorCount(pPathGradientBrush)
If (iCount=-1)
Return 0
Static Ptr := "UPtr"
VarSetCapacity(sColors, 8 * iCount, 0)
DllCall("gdiplus\GdipGetPathGradientSurroundColorsWithCount", Ptr, pPathGradientBrush, Ptr, &sColors, "intP", iCount)
Loop %iCount%
{
A := NumGet(&sColors, 8*(A_Index-1), "uint")
printList .= Format("{1:#x}", A) ","
}
Return Trim(printList, ",")
}
Gdip_GetHistogram(pBitmap, whichFormat, ByRef newArrayA, ByRef newArrayB, ByRef newArrayC, ByRef newArrayD:=0) {
Static sizeofUInt := 4
z := DllCall("gdiplus\GdipBitmapGetHistogramSize", "UInt", whichFormat, "UInt*", numEntries)
newArrayA := []
VarSetCapacity(ch0, numEntries * sizeofUInt, 0)
If (whichFormat<=2)
{
newArrayB := [], newArrayC := [], newArrayD := []
VarSetCapacity(ch1, numEntries * sizeofUInt, 0)
VarSetCapacity(ch2, numEntries * sizeofUInt, 0)
If (whichFormat<2)
VarSetCapacity(ch3, numEntries * sizeofUInt, 0)
}
E := DllCall("gdiplus\GdipBitmapGetHistogram", "Ptr", pBitmap, "UInt", whichFormat, "UInt", numEntries, "Ptr", &ch0
, "Ptr", (whichFormat<=2) ? &ch1 : 0
, "Ptr", (whichFormat<=2) ? &ch2 : 0
, "Ptr", (whichFormat<2) ?  &ch3 : 0)
If (E=1 && A_LastError=8)
E := 3
Loop %numEntries%
{
i := A_Index - 1
newArrayA[i] := NumGet(&ch0+0, i * sizeofUInt, "UInt")
If (whichFormat<=2)
{
newArrayB[i] := NumGet(&ch1+0, i * sizeofUInt, "UInt")
newArrayC[i] := NumGet(&ch2+0, i * sizeofUInt, "UInt")
If (whichFormat<2)
newArrayD[i] := NumGet(&ch3+0, i * sizeofUInt, "UInt")
}
}
Return E
}
Gdip_DrawRoundedLine(G, x1, y1, x2, y2, LineWidth, LineColor) {
pPen := Gdip_CreatePen(LineColor, LineWidth)
Gdip_DrawLine(G, pPen, x1, y1, x2, y2)
Gdip_DeletePen(pPen)
pPen := Gdip_CreatePen(LineColor, LineWidth/2)
Gdip_DrawEllipse(G, pPen, x1-LineWidth/4, y1-LineWidth/4, LineWidth/2, LineWidth/2)
Gdip_DrawEllipse(G, pPen, x2-LineWidth/4, y2-LineWidth/4, LineWidth/2, LineWidth/2)
Gdip_DeletePen(pPen)
}
Gdip_CreateBitmapFromGdiDib(BITMAPINFO, BitmapData) {
Static Ptr := "UPtr"
pBitmap := 0
gdipLastError := DllCall("gdiplus\GdipCreateBitmapFromGdiDib", Ptr, BITMAPINFO, Ptr, BitmapData, "UPtr*", pBitmap)
Return pBitmap
}
Gdip_DrawImageFX(pGraphics, pBitmap, dX:="", dY:="", sX:="", sY:="", sW:="", sH:="", matrix:="", pEffect:="", ImageAttr:=0, hMatrix:=0, Unit:=2) {
Static Ptr := "UPtr"
If !ImageAttr
{
if !IsNumber(Matrix)
ImageAttr := Gdip_SetImageAttributesColorMatrix(Matrix)
else if (Matrix != 1)
ImageAttr := Gdip_SetImageAttributesColorMatrix("1|0|0|0|0|0|1|0|0|0|0|0|1|0|0|0|0|0|" Matrix "|0|0|0|0|0|1")
} Else usrImageAttr := 1
if (sX="" && sY="")
sX := sY := 0
if (sW="" && sH="")
Gdip_GetImageDimensions(pBitmap, sW, sH)
if (!hMatrix && dX!="" && dY!="")
{
hMatrix := dhMatrix := Gdip_CreateMatrix()
Gdip_TranslateMatrix(dhMatrix, dX, dY, 1)
}
CreateRectF(sourceRect, sX, sY, sW, sH)
E := DllCall("gdiplus\GdipDrawImageFX"
, Ptr, pGraphics
, Ptr, pBitmap
, Ptr, &sourceRect
, Ptr, hMatrix ? hMatrix : 0
, Ptr, pEffect ? pEffect : 0
, Ptr, ImageAttr ? ImageAttr : 0
, "Uint", Unit)
If dhMatrix
Gdip_DeleteMatrix(dhMatrix)
If (ImageAttr && usrImageAttr!=1)
Gdip_DisposeImageAttributes(ImageAttr)
Return E
}
Gdip_BitmapApplyEffect(pBitmap, pEffect, x:="", y:="", w:="", h:="") {
If (InStr(pEffect, "err-") || !pEffect || !pBitmap)
Return 2
If (!x && !y && !w && !h)
none := 1
Else
CreateRect(Rect, x, y, x + w, y + h)
E := DllCall("gdiplus\GdipBitmapApplyEffect"
, "UPtr", pBitmap
, "UPtr", pEffect
, "UPtr", (none=1) ? 0 : &Rect
, "UPtr", 0
, "UPtr", 0
, "UPtr", 0)
Return E
}
COM_CLSIDfromString(ByRef CLSID, String) {
VarSetCapacity(CLSID, 16, 0)
E := DllCall("ole32\CLSIDFromString", "WStr", String, "UPtr", &CLSID)
Return E
}
Gdip_CreateEffect(whichFX, paramA, paramB, paramC:=0) {
Static gdipImgFX := {1:"633C80A4-1843-482b-9EF2-BE2834C5FDD4", 2:"63CBF3EE-C526-402c-8F71-62C540BF5142", 3:"718F2615-7933-40e3-A511-5F68FE14DD74", 4:"A7CE72A9-0F7F-40d7-B3CC-D0C02D5C3212", 5:"D3A1DBE1-8EC4-4c17-9F4C-EA97AD1C343D", 6:"8B2DD6C3-EB07-4d87-A5F0-7108E26A9C5F", 7:"99C354EC-2A31-4f3a-8C34-17A803B33A25", 8:"1077AF00-2848-4441-9489-44AD4C2D7A2C", 9:"537E597D-251E-48da-9664-29CA496B70F8", 10:"74D29D05-69A4-4266-9549-3CC52836B632", 11:"DD6A0022-58E4-4a67-9D9B-D48EB881A53D"}
Ptr := A_PtrSize=8 ? "UPtr" : "UInt"
Ptr2 := A_PtrSize=8 ? "Ptr*" : "PtrP"
pEffect := 0
r1 := COM_CLSIDfromString(eFXguid, "{" gdipImgFX[whichFX] "}" )
If r1
Return "err-" r1
If (A_PtrSize=4)
{
r2 := DllCall("gdiplus\GdipCreateEffect"
, "UInt", NumGet(eFXguid, 0, "UInt")
, "UInt", NumGet(eFXguid, 4, "UInt")
, "UInt", NumGet(eFXguid, 8, "UInt")
, "UInt", NumGet(eFXguid, 12, "UInt")
, Ptr2, pEffect)
} Else
{
r2 := DllCall("gdiplus\GdipCreateEffect"
, Ptr, &eFXguid
, Ptr2, pEffect)
}
If r2
Return "err-" r2
VarSetCapacity(FXparams, 16, 0)
If (whichFX=1)
{
NumPut(paramA, FXparams, 0, "Float")
NumPut(paramB, FXparams, 4, "Uchar")
} Else If (whichFX=2)
{
NumPut(paramA, FXparams, 0, "Float")
NumPut(paramB, FXparams, 4, "Float")
} Else If (whichFX=5)
{
NumPut(paramA, FXparams, 0, "Int")
NumPut(paramB, FXparams, 4, "Int")
} Else If (whichFX=6)
{
NumPut(paramA, FXparams, 0, "Int")
NumPut(paramB, FXparams, 4, "Int")
NumPut(paramC, FXparams, 8, "Int")
} Else If (whichFX=7)
{
NumPut(paramA, FXparams, 0, "Int")
NumPut(paramB, FXparams, 4, "Int")
NumPut(paramC, FXparams, 8, "Int")
} Else If (whichFX=8)
{
NumPut(paramA, FXparams, 0, "Int")
NumPut(paramB, FXparams, 4, "Int")
} Else If (whichFX=9)
{
NumPut(paramA, FXparams, 0, "Int")
NumPut(paramB, FXparams, 4, "Int")
NumPut(paramC, FXparams, 8, "Int")
} Else If (whichFX=11)
{
NumPut(paramA, FXparams, 0, "Int")
NumPut(paramB, FXparams, 4, "Int")
NumPut(paramC, FXparams, 8, "Int")
}
DllCall("gdiplus\GdipGetEffectParameterSize", Ptr, pEffect, "uint*", FXsize)
r3 := DllCall("gdiplus\GdipSetEffectParameters", Ptr, pEffect, Ptr, &FXparams, "UInt", FXsize)
If r3
{
Gdip_DisposeEffect(pEffect)
Return "err-" r3
}
Return pEffect
}
Gdip_DisposeEffect(pEffect) {
Static Ptr := "UPtr"
If (pEffect && !InStr(pEffect, "err"))
r := DllCall("gdiplus\GdipDeleteEffect", Ptr, pEffect)
Return r
}
GenerateColorMatrix(modus, bright:=1, contrast:=0, saturation:=1, alph:=1, chnRdec:=0, chnGdec:=0, chnBdec:=0) {
Static NTSCr := 0.308, NTSCg := 0.650, NTSCb := 0.095
matrix := ""
If (modus=2)
{
LGA := (bright<=1) ? bright/1.5 - 0.6666 : bright - 1
Ra := NTSCr + LGA
If (Ra<0)
Ra := 0
Ga := NTSCg + LGA
If (Ga<0)
Ga := 0
Ba := NTSCb + LGA
If (Ba<0)
Ba := 0
matrix := Ra "|" Ra "|" Ra "|0|0|" Ga "|" Ga "|" Ga "|0|0|" Ba "|" Ba "|" Ba "|0|0|0|0|0|" alph "|0|" contrast "|" contrast "|" contrast "|0|1"
} Else If (modus=3)
{
Ga := 0, Ba := 0, GGA := 0
Ra := bright
matrix := Ra "|" Ra "|" Ra "|0|0|" Ga "|" Ga "|" Ga "|0|0|" Ba "|" Ba "|" Ba "|0|0|0|0|0|" alph "|0|" GGA+0.01 "|" GGA "|" GGA "|0|1"
} Else If (modus=4)
{
Ra := 0, Ba := 0, GGA := 0
Ga := bright
matrix := Ra "|" Ra "|" Ra "|0|0|" Ga "|" Ga "|" Ga "|0|0|" Ba "|" Ba "|" Ba "|0|0|0|0|0|" alph "|0|" GGA "|" GGA+0.01 "|" GGA "|0|1"
} Else If (modus=5)
{
Ra := 0, Ga := 0, GGA := 0
Ba := bright
matrix := Ra "|" Ra "|" Ra "|0|0|" Ga "|" Ga "|" Ga "|0|0|" Ba "|" Ba "|" Ba "|0|0|0|0|0|" alph "|0|" GGA "|" GGA "|" GGA+0.01 "|0|1"
} Else If (modus=6)
{
matrix := "-1|0|0|0|0|0|-1|0|0|0|0|0|-1|0|0|0|0|0|" alph "|0|1|1|1|0|1"
} Else If (modus=1)
{
bL := bright, aL := alph
G := contrast, sL := saturation
sLi := 1 - saturation
bLa := bright - 1
If (sL>1)
{
z := (bL<1) ? bL : 1
sL := sL*z
If (sL<0.98)
sL := 0.98
y := z*(1 - sL)
mA := z*(y*NTSCr + sL + bLa + chnRdec)
mB := z*(y*NTSCr)
mC := z*(y*NTSCr)
mD := z*(y*NTSCg)
mE := z*(y*NTSCg + sL + bLa + chnGdec)
mF := z*(y*NTSCg)
mG := z*(y*NTSCb)
mH := z*(y*NTSCb)
mI := z*(y*NTSCb + sL + bLa + chnBdec)
mtrx:= mA "|" mB "|" mC "|  0   |0"
. "|" mD "|" mE "|" mF "|  0   |0"
. "|" mG "|" mH "|" mI "|  0   |0"
. "|  0   |  0   |  0   |" aL "|0"
. "|" G  "|" G  "|" G  "|  0   |1"
} Else
{
z := (bL<1) ? bL : 1
tR := NTSCr - 0.5 + bL/2
tG := NTSCg - 0.5 + bL/2
tB := NTSCb - 0.5 + bL/2
rB := z*(tR*sLi+bL*(1 - sLi) + chnRdec)
gB := z*(tG*sLi+bL*(1 - sLi) + chnGdec)
bB := z*(tB*sLi+bL*(1 - sLi) + chnBdec)
rF := z*(NTSCr*sLi + (bL/2 - 0.5)*sLi)
gF := z*(NTSCg*sLi + (bL/2 - 0.5)*sLi)
bF := z*(NTSCb*sLi + (bL/2 - 0.5)*sLi)
rB := rB*z+rF*(1 - z)
gB := gB*z+gF*(1 - z)
bB := bB*z+bF*(1 - z)
If (rB<0)
rB := 0
If (gB<0)
gB := 0
If (bB<0)
bB := 0
If (rF<0)
rF := 0
If (gF<0)
gF := 0
If (bF<0)
bF := 0
mtrx:= rB "|" rF "|" rF "|  0   |0"
. "|" gF "|" gB "|" gF "|  0   |0"
. "|" bF "|" bF "|" bB "|  0   |0"
. "|  0   |  0   |  0   |" aL "|0"
. "|" G  "|" G  "|" G  "|  0   |1"
}
matrix := StrReplace(mtrx, A_Space)
} Else If (modus=0)
{
s1 := contrast
s2 := saturation
s3 := bright
aL := alph
s1 := s2*sin(s1)
sc := 1-s2
r := NTSCr*sc-s1
g := NTSCg*sc-s1
b := NTSCb*sc-s1
rB := r+s2+3*s1
gB := g+s2+3*s1
bB := b+s2+3*s1
mtrx :=   rB "|" r  "|" r  "|  0   |0"
. "|" g  "|" gB "|" g  "|  0   |0"
. "|" b  "|" b  "|" bB "|  0   |0"
. "|  0   |  0   |  0   |" aL "|0"
. "|" s3 "|" s3 "|" s3 "|  0   |1"
matrix := StrReplace(mtrx, A_Space)
} Else If (modus=7)
{
matrix := "0|0|0|0|0"
. "|0|0|0|0|0"
. "|0|0|0|0|0"
. "|1|1|1|25|0"
. "|0|0|0|0|1"
} Else If (modus=8)
{
matrix := "0.39|0.34|0.27|0|0"
. "|0.76|0.58|0.33|0|0"
. "|0.19|0.16|0.13|0|0"
. "|0|0|0|" alph "|0"
. "|0|0|0|0|1"
} Else If (modus=9)
{
matrix := "1|0|0|0|0"
. "|0|1|0|0|0"
. "|0|0|1|0|0"
. "|0|0|0|" alph "|0"
. "|0|0|0|0|1"
}
Return matrix
}
Gdip_CompareBitmaps(pBitmapA, pBitmapB, accuracy:=25) {
If (!pBitmapA || !pBitmapB)
Return -1
If (accuracy>99)
accuracy := 100
Else If (accuracy<5)
accuracy := 5
Gdip_GetImageDimensions(pBitmapA, WidthA, HeightA)
Gdip_GetImageDimensions(pBitmapB, WidthB, HeightB)
If (accuracy!=100)
{
pBitmap1 := Gdip_ResizeBitmap(pBitmapA, Floor(WidthA*(accuracy/100)), Floor(HeightA*(accuracy/100)), 0, 5)
pBitmap2 := Gdip_ResizeBitmap(pBitmapB, Floor(WidthB*(accuracy/100)), Floor(HeightB*(accuracy/100)), 0, 5)
If (!pBitmap1 || !pBitmap2)
{
Gdip_DisposeImage(pbitmap1, 1)
Gdip_DisposeImage(pbitmap2, 1)
Return -1
}
} Else
{
pBitmap1 := pBitmapA
pBitmap2 := pBitmapB
}
Gdip_GetImageDimensions(pBitmap1, Width1, Height1)
Gdip_GetImageDimensions(pBitmap2, Width2, Height2)
if (!Width1 || !Height1 || !Width2 || !Height2
|| Width1 != Width2 || Height1 != Height2)
{
If (accuracy!=100)
{
Gdip_DisposeImage(pBitmap1, 1)
Gdip_DisposeImage(pBitmap2, 1)
}
Return -1
}
E1 := Gdip_LockBits(pBitmap1, 0, 0, Width1, Height1, Stride1, Scan01, BitmapData1)
E2 := Gdip_LockBits(pBitmap2, 0, 0, Width2, Height2, Stride2, Scan02, BitmapData2)
If (E1 || E2)
{
If !E1
Gdip_UnlockBits(pBitmap1, BitmapData1)
If !E2
Gdip_UnlockBits(pBitmap2, BitmapData2)
If (accuracy!=100)
{
Gdip_DisposeImage(pBitmap1, 1)
Gdip_DisposeImage(pBitmap2, 1)
}
Return -1
}
z := 0
Loop %Height1%
{
y++
Loop %Width1%
{
Gdip_FromARGB(Gdip_GetLockBitPixel(Scan01, A_Index-1, y-1, Stride1), A1, R1, G1, B1)
Gdip_FromARGB(Gdip_GetLockBitPixel(Scan02, A_Index-1, y-1, Stride2), A2, R2, G2, B2)
z += Abs(A2-A1) + Abs(R2-R1) + Abs(G2-G1) + Abs(B2-B1)
}
}
Gdip_UnlockBits(pBitmap1, BitmapData1)
Gdip_UnlockBits(pBitmap2, BitmapData2)
If (accuracy!=100)
{
Gdip_DisposeImage(pBitmap1)
Gdip_DisposeImage(pBitmap2)
}
Return z/(Width1*Width2*3*255/100)
}
Gdip_RetrieveBitmapChannel(pBitmap, channel, PixelFormat:=0) {
If !pBitmap
Return
Gdip_GetImageDimensions(pBitmap, imgW, imgH)
If (!imgW || !imgH)
Return
newBitmap := Gdip_CreateBitmap(imgW, imgH, PixelFormat)
If !newBitmap
Return
G := Gdip_GraphicsFromImage(newBitmap, 7)
If !G
{
Gdip_DisposeImage(newBitmap, 1)
Return
}
If (channel=1)
matrix := GenerateColorMatrix(3)
Else If (channel=2)
matrix := GenerateColorMatrix(4)
Else If (channel=3)
matrix := GenerateColorMatrix(5)
Else If (channel=4)
matrix := GenerateColorMatrix(7)
Else Return
Gdip_GraphicsClear(G, "0xff000000")
E := Gdip_DrawImage(G, pBitmap, 0, 0, imgW, imgH, 0, 0, imgW, imgH, matrix)
If E
{
Gdip_DisposeImage(newBitmap, 1)
Return
}
Gdip_DeleteGraphics(G)
Return newBitmap
}
Gdip_RenderPixelsOpaque(pBitmap, pBrush:=0, alphaLevel:=0, PixelFormat:=0) {
Gdip_GetImageDimensions(pBitmap, imgW, imgH)
newBitmap := Gdip_CreateBitmap(imgW, imgH, PixelFormat)
If newBitmap
G := Gdip_GraphicsFromImage(newBitmap, 7)
If (!newBitmap || !G)
{
Gdip_DisposeImage(newBitmap, 1)
Gdip_DeleteGraphics(G)
Return
}
If alphaLevel
matrix := GenerateColorMatrix(0, 0, 0, 1, alphaLevel)
Else
matrix := GenerateColorMatrix(0, 0, 0, 1, 25)
If pBrush
Gdip_FillRectangle(G, pBrush, 0, 0, imgW, imgH)
E := Gdip_DrawImage(G, pBitmap, 0, 0, imgW, imgH, 0, 0, imgW, imgH, matrix)
Gdip_DeleteGraphics(G)
If E
{
Gdip_DisposeImage(newBitmap, 1)
Return
}
Return newBitmap
}
Gdip_TestBitmapUniformity(pBitmap, HistogramFormat:=3, ByRef maxLevelIndex:=0, ByRef maxLevelPixels:=0) {
If !pBitmap
Return -1
LevelsArray := []
maxLevelIndex := maxLevelPixels := nrPixels := 9
Gdip_GetImageDimensions(pBitmap, Width, Height)
E := Gdip_GetHistogram(pBitmap, HistogramFormat, LevelsArray, 0, 0)
If E
Return -2
Loop 256
{
nrPixels := Round(LevelsArray[A_Index - 1])
If (nrPixels>0)
histoList .= nrPixels "." A_Index - 1 "|"
}
Sort histoList, NURD|
histoList := Trim(histoList, "|")
histoListSortedArray := StrSplit(histoList, "|")
maxLevel := StrSplit(histoListSortedArray[1], ".")
maxLevelIndex := maxLevel[2]
maxLevelPixels := maxLevel[1]
pixelsThreshold := Round((Width * Height) * 0.0005) + 1
If (Floor(histoListSortedArray[2])<pixelsThreshold)
Return 1
Else
Return 0
}
Gdip_SetAlphaChannel(pBitmap, pBitmapMask, invertAlphaMask:=0, replaceSourceAlphaChannel:=0, whichChannel:=1) {
static mCodeFunc := 0
if (mCodeFunc=0)
{
if (A_PtrSize=8)
base64enc := "
      (LTrim Join
      2,x64:QVdBVkFVQVRVV1ZTRItsJGhJicuLTCR4SInWg/kBD4TZAQAAg/kCD4SyAAAAg/kDD4TRAQAAg/kEuBgAAAAPRMiDfCRwAQ+EowAAAEWFwA+OZgEAAEWNcP9NY8Ax7UG8/wAAAEqNHIUAAAAAMf9mkEWFyX5YQYP9AQ+E2QAAAEyNB
      K0AAAAAMdIPH4AAAAAAR4sUA0KLBAZFidfT+EHB7xgPtsBCjYQ4Af///4XAD0jHQYHi////AIPCAcHgGEQJ0EOJBANJAdhBOdF1w0iNRQFMOfUPhOEAAABIicXrkYN8JHABuQgAAAAPhV3///9FhcAPjsMAAABBjXj/TWPAMdtOjRSFAAAA
      AA8fgAAAAABFhcl+MUGD/QEPhLEAAABIjQSdAAAAAEUxwGYPH0QAAIsUBkGDwAHT+kGIVAMDTAHQRTnBdepIjUMBSDnfdGxIicPrvA8fQABIjRStAAAAAEUxwA8fRAAARYsUE4sEFkWJ19P4QcHvGA+2wEKNhDgB////RYnnhcAPSMdBgeL
      ///8AQYPAAUEpx0SJ+MHgGEQJ0EGJBBNIAdpFOcF1ukiNRQFMOfUPhR////+4AQAAAFteX11BXEFdQV5BX8MPHwBIjRSdAAAAAEUxwA8fRAAAiwQWQYPAAdP499BBiEQTA0wB0kU5wXXo6Un///+5EAAAAOk6/v//McnpM/7//w==
)"
else
base64enc := "
      (LTrim Join
      2,x86:VVdWU4PsBIN8JDABD4T1AQAAg3wkMAIPhBwBAACDfCQwAw+E7AEAAIN8JDAEuBgAAAAPRUQkMIlEJDCDfCQsAQ+EBgEAAItUJCCF0g+OiQAAAItEJCDHBCQAAAAAjSyFAAAAAI10JgCLRCQkhcB+XosEJItcJBgx/400hQAAAAAB8wN0JByDfCQ
      oAXRjjXYAixOLBg+2TCQw0/iJ0cHpGA+2wI2ECAH///+5AAAAAIXAD0jBgeL///8Ag8cBAe7B4BgJwokTAes5fCQkdcKDBCQBiwQkOUQkIHWNg8QEuAEAAABbXl9dw420JgAAAACQixOLBg+2TCQw0/iJ0cHpGA+2wI2ECAH///+5AAAAAIXAD0jBuf8A
      AACB4v///wAB7oPHASnBicjB4BgJwokTAes5fCQkdbnrlYN8JCwBx0QkMAgAAAAPhfr+//+LTCQghcl+hzH/i0QkIItsJCSJPCSLTCQwjTSFAAAAAI10JgCF7X42g3wkKAGLBCR0Sot8JByNFIUAAAAAMdsB1wNUJBiNtCYAAAAAiweDwwEB99P4iEIDA
      fI53XXugwQkAYsEJDlEJCB1uYPEBLgBAAAAW15fXcONdCYAi1wkHMHgAjHSAcMDRCQYiceNtCYAAAAAiwODwgEB89P499CIRwMB9znVdeyDBCQBiwQkOUQkIA+Fa////+uwx0QkMBAAAADpJ/7//8dEJDAAAAAA6Rr+//8=
)"
mCodeFunc := Gdip_RunMCode(base64enc)
}
Gdip_GetImageDimensions(pBitmap, w, h)
Gdip_GetImageDimensions(pBitmapMask, w2, h2)
If (w2!=w || h2!=h || !pBitmap || !pBitmapMask)
Return 0
E1 := Gdip_LockBits(pBitmap, 0, 0, w, h, stride, iScan, iData)
E2 := Gdip_LockBits(pBitmapMask, 0, 0, w, h, stride, mScan, mData)
If (!E1 && !E2)
r := DllCall(mCodeFunc, "UPtr", iScan, "UPtr", mScan, "Int", w, "Int", h, "Int", invertAlphaMask, "Int", replaceSourceAlphaChannel, "Int", whichChannel)
If !E1
Gdip_UnlockBits(pBitmap, iData)
If !E2
Gdip_UnlockBits(pBitmapMask, mData)
return r
}
Gdip_BlendBitmaps(pBitmap, pBitmap2Blend, blendMode) {
static mCodeFunc := 0
if (mCodeFunc=0)
{
if (A_PtrSize=8)
base64enc := "
      (LTrim Join
      2,x64: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
)"
else
base64enc := "
      (LTrim Join
      2,x86:VVdWU4PsMItcJEyF2w+OdAIAAItUJFCF0g+OaAIAAItEJEzHRCQkAAAAAMHgAolEJAiNtgAAAACLRCQki3QkRIlMJAQx/4n9weACAcYDRCRIiQQkjXQmAIsOhckPhPgBAACLBCSJz8HvGIsYifqJ2MHoGDjCD0LHiEQkFITAD4QUAgAAidqJz4nYweoIwe8QiVQkLA+218HoEIN8JFQBiVQkGA+204lUJByJ+g+2+g+21YlEJCgPtsmJVCQgD7bAD4QSAQAAg3wkVAIPhM8BAACDfCRUAw+EBAIAAI
      N8JFQED4RRAgAAg3wkVAUPhM4CAACDfCRUBg+E8wIAAIN8JFQHD4R8AwAAg3wkVAgPhLoDAACDfCRUCQ+EfwQAAIN8JFQKD4RYBQAAg3wkVAsPhH4GAACDfCRUDA+EAAYAAIN8JFQND4TABgAAg3wkVA4PhPIHAACDfCRUDw+EWwcAAIN8JFQQD4R3CAAAg3wkVBEPhLAIAACDfCRUEg+FuAMAADn4D470CAAAu/8AAAApw4nYKfiJRCQMi1wkGIt8JCC4/wAAADn7D46/CAAAKdgp+IlEJBCLRCQcuv8AAA
      A5yA+OlwgAACnCKcqJVCQE6VYDAACNdCYAkItcJBg5+A9O+InQOdMPTsOJfCQMiUQkEItEJBw5yInCD0/RiVQkBItcJAy4AAAAAItMJAS/AAAAAIXbD0nDi1wkEIXbiUQkDA9J+7sAAAAAhcmJ2g9J0cHgEIl8JBCJw8HnCIlUJAQPtsqB4wAA/wAPt/+LRCQUCdnB4BgJwQn5iQ6LRCQIg8UBAQQkAcY5bCRQD4Xo/f//g0QkJAGLTCQEi0QkJDlEJEwPhbH9//+DxDC4AQAAAFteX13DjXQmAMcGAAAAAO
      u6D6/4u4GAgIAPr0wkHIn49+PB6geJVCQMi1QkGA+vVCQgidD344nIweoHiVQkEPfjweoHiVQkBOkj////jXQmAAHHuP8AAACLVCQYgf//AAAAD0z4A1QkIIH6/wAAAA9M0ANMJByNnwH///+B+f8AAACJXCQMD0zIjZoB////iVwkEI2BAf///4lEJATpzv7//420JgAAAAC6/wAAACn6idPB4wgp04najVgBidCZ9/u7/wAAALr/AAAAKcO4AAAAAA9JwytUJCCLXCQYiUQkDInQg8MBweAIKdCZ9/u7/w
      AAALr/AAAAKcO4AAAAAA9JwynKi0wkHIlEJBCJ0IPBAcHgCCnQmff5uv8AAAApwrgAAAAAD0nCiUQkBOk//v//OfiLXCQYD034i0QkIDnDiXwkDA9Nw4lEJBCLRCQcOciJwg9M0YlUJATpEf7//2aQuv8AAAC7gYCAgCnCuP8AAAAp+InXD6/4ifj364n4wfgfAfrB+gcp0Lr/AAAAK1QkGAX/AAAAideJRCQMuP8AAAArRCQgD6/4ifj364n4wfgfAfrB+gcp0Lr/AAAAK1QkHAX/AAAAiUQkELj/AAAAKc
      iJ0Q+vyInI9+uNHArB+R/B+wcp2Y2B/wAAAIlEJATpe/3//wH4u/8AAACLVCQcPf8AAAAPTtiLRCQYA0QkID3/AAAAiVwkDLv/AAAAD07YAcq4/wAAAIH6/wAAAA9OwolcJBCJRCQE6TL9//+D+H4Pj3QBAAAPr/i6gYCAgI0EP/fiweoHiVQkDItEJBiD+H4PjxgBAAAPr0QkILqBgICAAcD34sHqB4lUJBCLRCQcg/h+f08Pr8iNBAm6gYCAgPfiweoHiVQkBItEJAyFwHkIgUQkDP8AAACLRCQQhcB5CQ
      X/AAAAiUQkEItEJASFwA+Jqfz//wX/AAAAiUQkBOmb/P//uv8AAAC4/wAAACtUJBwpyInRuoGAgIAPr8gByYnI9+qNBArB+R/B+AeJyinCjYL/AAAAiUQkBOuMg/9+D44+AQAAuv8AAAApwrj/AAAAKfgPr8K6gYCAgI0cAInY9+qJ2MH4HwHai1wkIMH6BynQBf8AAACJRCQMg/t+D48fAQAAi0QkGLqBgICAD6/DAcD34sHqB4lUJBCD+X4Pj1////8Pr0wkHOkJ////uv8AAAC4/wAAACtUJBgrRCQgD6
      /CuoGAgICNHACJ2PfqidjB+B8B2sH6BynQBf8AAACJRCQQ6cL+//+6/wAAACnCuP8AAAAp+A+vwrqBgICAjRwAidj36onYwfgfAdrB+gcp0AX/AAAAiUQkDOlp/v//uv8AAAC7AAD/ACn6vwAAAAA5wrj/AAAAifoPTccPTd+/AP8AAIlEJAy4/wAAACtEJCA7RCQYuP8AAAAPTcIPTfqJRCQQuP8AAAApyDtEJBy4/wAAAA9NwolEJASJweln+///D6/HuoGAgICLXCQgAcD34sHqB4lUJAyD+34PjuH+//
      +6/wAAALj/AAAAK1QkGCtEJCAPr8K6gYCAgI0cAInY9+qJ2MH4HwHawfoHKdAF/wAAAIlEJBDpvf7//4n6uwABAADB4ggp+onfKceJ0Jn3/7//AAAAido9/wAAAA9Px4t8JCArVCQYiUQkDIn4weAIKfiJ15n3/7//AAAAPf8AAAAPT8eJRCQQicjB4AgpyInZK0wkHJn3+br/AAAAPf8AAAAPTtCJVCQE6U36//+NFEe4/gEAAIt8JBiB+v4BAAAPT9CNmgH///+JXCQMi1wkII0Ue4H6/gEAAA9P0I2aAf
      ///4lcJBCLXCQcjRRZgfr+AQAAD0/QjYIB////iUQkBOkf/f//i1QkKIHigAAAAIlUJAQPhPsAAACJ+sHiCCn6vwABAAApx4nQjTw/mff/v/8AAAA9/wAAAA9Px4lEJAyLfCQsgeeAAAAAD4VdAQAAuv8AAAArVCQgidDB4Agp0A+2141UEgGJVCQEmfd8JAS6/wAAACnCD0n6iXwkEIHjgAAAAA+FDAEAALr/AAAAKcqLTCQcidDB4AiNTAkBKdCZ9/m6/wAAACnCD0naiVwkBOlE+f//jRw4D6/HiVwkBL
      uBgICAi3wkBPfjidCLVCQgwegHAcApx4tEJBiJfCQMiccPr8IB1/fjidDB6AcBwCnHi0QkHIl8JBCNPAgPr8H344nQwegHAcApx4l8JATpEPz//7r/AAAAKfqJ18HiCCn6jXwAAYnQmff/v/8AAAApx4tEJAQPSceJRCQM6f7+//+J+o1YAcHiCCn6v/8AAACJ0Jn3+4tcJCA9/wAAAA9Px4lEJAyJ2MHgCCnYi1wkGJmDwwH3+z3/AAAAD0/HiUQkEInIweAIKciLTCQcg8EB6f79//+JyMHgCCnIuQABAA
      ArTCQcAcnp5/3//4t8JCC6AAEAACtUJBiJ+MHgCCn4jTwSmff/v/8AAAA9/wAAAA9Px4lEJBDpof7//4nCifspwyn6OfiLfCQgD07Ti1wkGIlUJAyJ2In6Kdop+Dn7i1wkHA9OwonKKdqJRCQQidgpyDnLD07CiUQkBOkD+///Kce4AAAAALsAAAAAD0nHiUQkDItEJCArRCQYD0nYK0wkHLgAAAAAD0nBiVwkEIlEJATpovf//ynKK1QkHIlUJATpvfr//ytEJCArRCQYiUQkEOk49///uv8AAAAp+inCiV
      QkDOkJ9///
)"
mCodeFunc := Gdip_RunMCode(base64enc)
}
Gdip_GetImageDimensions(pBitmap, w, h)
Gdip_GetImageDimensions(pBitmap2Blend, w2, h2)
If (w2!=w || h2!=h || !pBitmap || !pBitmap2Blend)
Return 0
E1 := Gdip_LockBits(pBitmap, 0, 0, w, h, stride, iScan, iData)
E2 := Gdip_LockBits(pBitmap2Blend, 0, 0, w, h, stride, mScan, mData)
If (!E1 && !E2)
r := DllCall(mCodeFunc, "UPtr", iScan, "UPtr", mScan, "Int", w, "Int", h, "Int", blendMode)
If !E1
Gdip_UnlockBits(pBitmap, iData)
If !E2
Gdip_UnlockBits(pBitmap2Blend, mData)
return r
}
Gdip_BoxBlurBitmap(pBitmap, passes) {
static mCodeFunc := 0
if (mCodeFunc=0)
{
if (A_PtrSize=8)
base64enc := "
      (LTrim Join
      2,x64:QVdBVkFVQVRVV1ZTSIPsWESLnCTAAAAASImMJKAAAABEicCJlCSoAAAARImMJLgAAABFhdsPjtoDAABEiceD6AHHRCQ8AAAAAEG+q6qqqkEPr/lBD6/BiXwkBInXg+8BiUQkJIn4iXwkOEiNdIEESPfYSIl0JEBIjTSFAAAAAI0EvQAAAABJY/lImEiJdCRISI1EBvxIiXwkCEiJRCQwRInI99hImEiJRCQQDx9EAABIi0QkQMdEJCAAAAAASIlEJBhIi0QkSEiD6ARIiUQkKItEJASFwA+OegEAAA8fQABEi4wkqAAAAEWFyQ+OPwMAAEiLRCQoTIt8JBgx9jHbRTHbRTHSRTHJRTHATAH4Mckx0mYPH0QAAEWJ1UQPtlADRYn
      cRA+2WAJEAepEAeGJ3Q+2WAFEAdJBAeiJ9w+2MEkPr9ZBAflIg8AESMHqIYhQ/0KNFBlEieFJD6/WSMHqIYhQ/kGNFBhBiehJD6/WSMHqIYhQ/UGNFDFBiflJD6/WSMHqIYhQ/ESJ6kw5+HWJi3wkOEiLRCQwMfYx20gDRCQYRTHbRTHSRTHJRTHAMckx0g8fgAAAAABFiddED7ZQA0WJ3UQPtlgCRAH6RAHpQYncD7ZYAUQB0kUB4In1D7YwSQ+v1kEB6YPvAUiD6ARIweohiFAHQo0UGUSJ6UkPr9ZIweohiFAGQY0UGEWJ4EkPr9ZIweohiFAFQY0UMUGJ6UkPr9ZIweohiFAERIn6g///dYWLvCS4AAAASItcJAgBfCQgi0QkIEgB
      XCQYO0QkBA+Miv7//0SLhCSoAAAAx0QkGAMAAADHRCQgAAAAAEWFwA+OiAEAAGYPH4QAAAAAAItUJASF0g+OpAAAAEhjRCQYMf8x9jHbSAOEJKAAAABFMdtFMdIxyUUxyUUxwDHSkEWJ10QPthBFid1ED7ZY/0QB+kQB6UGJ3A+2WP5EAdJFAeCJ9Q+2cP1JD6/WQQHpA7wkuAAAAEjB6iGIEEKNFBlEielJD6/WSMHqIYhQ/0GNFBhFieBJD6/WSMHqIYhQ/kGNFDFBielJD6/WSMHqIYhQ/UgDRCQIRIn6O3wkBHyAi0wkJIXJD4ioAAAATGNUJCRIY0QkGDH/MfYx20Ux20UxyUUxwEwB0DHJSAOEJKAAAAAx0g8fQABFid9ED7YYQ
      YndD7ZY/0QB+kQB6UGJ9A+2cP5EAdpFAeCJ/Q+2eP1JD6/WQQHpSMHqIYgQjRQZSItMJBBJD6/WSQHKSMHqIYhQ/0GNFDBFieBJD6/WSMHqIYhQ/kGNFDlBielJD6/WSMHqIYhQ/UgByESJ+kSJ6UWF0nmEg0QkIAGLRCQgg0QkGAQ5hCSoAAAAD4WB/v//g0QkPAGLRCQ8OYQkwAAAAA+Fm/z//0iDxFhbXl9dQVxBXUFeQV/DZi4PH4QAAAAAAESLVCQ4RYXSD4j1/f//6Uz9//8=
)"
else
base64enc := "
      (LTrim Join
      2,x86:VVdWU4PsPItsJGCLRCRYhe0PjncEAACLfCRcx0QkNAAAAAAPr/iD6AEPr0QkXIl8JCSLfCRUiUQkLItEJFCD7wGJfCQwi3wkVI0EuIlEJDiLRCQ4x0QkKAAAAACJRCQgi0QkJIXAD47pAQAAjXQmAIt0JFSF9g+OJAQAAMdEJAwAAAAAi0wkKDHtMf/HRCQYAAAAAANMJFAx9jHAx0QkFAAAAADHRCQQAAAAAI10JgCLVCQMD7ZZA4k0JIPBBA+2cf6JfCQEiVQkHAHCD7Z5/QHaiVwkDLurqqqqidCJbCQID7Zp/Pfji1wkEAMcJNHqiFH/idq7q6qqqgHyidD344tcJBQDXCQE0eqIUf6J2rurqqqqAfqJ0Pfj0eqIUf2LVCQ
      YA1QkCAHqidD344scJItEJByJXCQQi1wkBNHqiVwkFItcJAiIUfyJXCQYO0wkIA+FWf///4tEJDDHBCQAAAAAMe0x/8dEJBwAAAAAi0wkIDH2x0QkGAAAAADHRCQUAAAAAIlEJAQxwI22AAAAAIscJA+2Uf+JdCQIg+kED7ZxAol8JAyJFCSNFBgDFCSJ0LqrqqqqD7Z5AYlsJBD34g+2KYNsJAQB0eqIUQOLVCQUA1QkCAHyidC6q6qqqvfi0eqIUQKLVCQYA1QkDAH6idC6q6qqqvfi0eqIUQGLVCQcA1QkEAHqidC6q6qqqvfiidiLXCQIiVwkFItcJAzR6ogRi1QkBIlcJBiLXCQQiVwkHIP6/w+FVf///4t8JFwBfCQoAXwkIItE
      JCg7RCQkD4wb/v//i0QkUItcJFTHRCQoAAAAAPfYiUQkDIXbD44IAgAAjXQmAJCLVCQkhdIPjugAAAAx9otMJAzHRCQIAAAAADHtx0QkGAAAAAAx/zHAx0QkFAAAAAD32cdEJBAAAAAAiTQkjXYAi1QkCA+2cQOJfCQEixwkD7Z5AYlUJCABwgHyiXQkCL6rqqqqidCJXCQcD7ZZAvfmi3QkHItEJBCJHCSJ6w+2KQHwiXQkEIt0JAzR6ohRA4sUJAHCidC6q6qqqvfii0QkFANEJATR6ohRAonCAfqJ0Lqrqqqq9+KLRCQYiVwkGAHY0eqIUQGJwgHqidC6q6qqqvfii0QkINHqiBGLVCQEA0wkXIlUJBSNFDE5VCQkD49M////i0wkL
      IXJD4jrAAAAMfbHRCQQAAAAAItMJCwx7cdEJBwAAAAAK0wkDDH/McDHRCQYAAAAAMdEJBQAAAAAiTQkjXQmAJCLHCSLVCQQiXwkBA+2cQMPtnkBiWwkCIlcJCAPtlkCiXQkEA+2KYkcJInTAcIB8r6rqqqqidD35ot0JCCLRCQUAfCJdCQUi3QkDNHqiFEDixQkAcKJ0Lqrqqqq9+KLRCQYA0QkBNHqiFECicIB+onQuquqqqr34otEJBwDRCQI0eqIUQGJwgHqidC6q6qqqvfiidjR6ogRi1QkBCtMJFyJVCQYi1QkCAHOiVQkHA+JTf///4NEJCgBi0QkKINsJAwEOUQkVA+F/f3//4NEJDQBi0QkNDlEJGAPhcL7//+DxDxbXl9dw4
      20JgAAAACNdgCLfCQwhf8PiI/9///ppvz//w==
)"
mCodeFunc := Gdip_RunMCode(base64enc)
}
Gdip_GetImageDimensions(pBitmap,w,h)
E1 := Gdip_LockBits(pBitmap,0,0,w,h,stride,iScan,iData)
If E1
Return
r := DllCall(mCodeFunc, "UPtr",iScan, "Int",w, "Int",h, "Int",stride, "Int",passes)
Gdip_UnlockBits(pBitmap,iData)
return r
}
Gdip_RunMCode(mcode) {
static e := {1:4, 2:1}
, c := (A_PtrSize=8) ? "x64" : "x86"
if (!regexmatch(mcode, "^([0-9]+),(" c ":|.*?," c ":)([^,]+)", m))
return
if (!DllCall("crypt32\CryptStringToBinary", "str", m3, "uint", StrLen(m3), "uint", e[m1], "ptr", 0, "uintp", s, "ptr", 0, "ptr", 0))
return
p := DllCall("GlobalAlloc", "uint", 0, "ptr", s, "ptr")
DllCall("VirtualProtect", "ptr", p, "ptr", s, "uint", 0x40, "uint*", op)
if (DllCall("crypt32\CryptStringToBinary", "str", m3, "uint", StrLen(m3), "uint", e[m1], "ptr", p, "uint*", s, "ptr", 0, "ptr", 0))
return p
DllCall("GlobalFree", "ptr", p)
}
calcIMGdimensions(imgW, imgH, givenW, givenH, ByRef ResizedW, ByRef ResizedH) {
PicRatio := Round(imgW/imgH, 5)
givenRatio := Round(givenW/givenH, 5)
If (imgW <= givenW) && (imgH <= givenH)
{
ResizedW := givenW
ResizedH := Round(ResizedW / PicRatio)
If (ResizedH>givenH)
{
ResizedH := (imgH <= givenH) ? givenH : imgH
ResizedW := Round(ResizedH * PicRatio)
}
} Else If (PicRatio > givenRatio)
{
ResizedW := givenW
ResizedH := Round(ResizedW / PicRatio)
} Else
{
ResizedH := (imgH >= givenH) ? givenH : imgH
ResizedW := Round(ResizedH * PicRatio)
}
}
GetWindowRect(hwnd, ByRef W, ByRef H) {
If !hwnd
Return
size := VarSetCapacity(rect, 16, 0)
er := DllCall("dwmapi\DwmGetWindowAttribute"
, "UPtr", hWnd
, "UInt", 9
, "UPtr", &rect
, "UInt", size
, "UInt")
If er
DllCall("GetWindowRect", "UPtr", hwnd, "UPtr", &rect, "UInt")
r := []
r.x1 := NumGet(rect, 0, "Int"), r.y1 := NumGet(rect, 4, "Int")
r.x2 := NumGet(rect, 8, "Int"), r.y2 := NumGet(rect, 12, "Int")
r.w := Abs(max(r.x1, r.x2) - min(r.x1, r.x2))
r.h := Abs(max(r.y1, r.y2) - min(r.y1, r.y2))
W := r.w
H := r.h
Return r
}
Gdip_BitmapConvertGray(pBitmap, hue:=0, vibrance:=-40, brightness:=1, contrast:=0, KeepPixelFormat:=0) {
Gdip_GetImageDimensions(pBitmap, Width, Height)
If (KeepPixelFormat=1)
PixelFormat := Gdip_GetImagePixelFormat(pBitmap, 1)
If StrLen(KeepPixelFormat)>3
PixelFormat := KeepPixelFormat
newBitmap := Gdip_CreateBitmap(Width, Height, PixelFormat)
G := Gdip_GraphicsFromImage(newBitmap, InterpolationMode)
If (hue!=0 || vibrance!=0)
pEffect := Gdip_CreateEffect(6, hue, vibrance, 0)
matrix := GenerateColorMatrix(2, brightness, contrast)
If pEffect
{
E := Gdip_DrawImageFX(G, pBitmap, 0, 0, 0, 0, Width, Height, matrix, pEffect)
Gdip_DisposeEffect(pEffect)
} Else
E := Gdip_DrawImage(G, pBitmap, 0, 0, Width, Height, 0, 0, Width, Height, matrix)
Gdip_DeleteGraphics(G)
Return newBitmap
}
Gdip_BitmapSetColorDepth(pBitmap, bitsDepth, useDithering:=1) {
ditheringMode := (useDithering=1) ? 9 : 1
If (useDithering=1 && bitsDepth=16)
ditheringMode := 2
Colors := 2**bitsDepth
If bitsDepth Between 2 and 4
bitsDepth := "40s"
If bitsDepth Between 5 and 8
bitsDepth := "80s"
If (bitsDepth="BW")
E := Gdip_BitmapConvertFormat(pBitmap, 0x30101, ditheringMode, 2, 2, 2, 2, 0, 0)
Else If (bitsDepth=1)
E := Gdip_BitmapConvertFormat(pBitmap, 0x30101, ditheringMode, 1, 2, 1, 2, 0, 0)
Else If (bitsDepth="40s")
E := Gdip_BitmapConvertFormat(pBitmap, 0x30402, ditheringMode, 1, Colors, 1, Colors, 0, 0)
Else If (bitsDepth="80s")
E := Gdip_BitmapConvertFormat(pBitmap, 0x30803, ditheringMode, 1, Colors, 1, Colors, 0, 0)
Else If (bitsDepth=16)
E := Gdip_BitmapConvertFormat(pBitmap, 0x21005, ditheringMode, 1, Colors, 1, Colors, 0, 0)
Else If (bitsDepth=24)
E := Gdip_BitmapConvertFormat(pBitmap, 0x21808, 2, 1, 0, 0, 0, 0, 0)
Else If (bitsDepth=32)
E := Gdip_BitmapConvertFormat(pBitmap, 0x26200A, 2, 1, 0, 0, 0, 0, 0)
Else
E := -1
Return E
}
Gdip_BitmapConvertFormat(pBitmap, PixelFormat, DitherType, DitherPaletteType, PaletteEntries, PaletteType, OptimalColors, UseTransparentColor:=0, AlphaThresholdPercent:=0) {
VarSetCapacity(hPalette, 4 * PaletteEntries + 8, 0)
NumPut(PaletteType, &hPalette, 0, "uint")
NumPut(PaletteEntries, &hPalette, 4, "uint")
NumPut(0, &hPalette, 8, "uint")
Static Ptr := "UPtr"
E1 := DllCall("gdiplus\GdipInitializePalette", "UPtr", &hPalette, "uint", PaletteType, "uint", OptimalColors, "Int", UseTransparentColor, Ptr, pBitmap)
E2 := DllCall("gdiplus\GdipBitmapConvertFormat", Ptr, pBitmap, "uint", PixelFormat, "uint", DitherType, "uint", DitherPaletteType, "uPtr", &hPalette, "float", AlphaThresholdPercent)
E := E1 ? E1 : E2
Return E
}
Gdip_GetImageThumbnail(pBitmap, W, H) {
DllCall("gdiplus\GdipGetImageThumbnail"
,"UPtr",pBitmap
,"UInt",W
,"UInt",H
,"UPtr*",pThumbnail
,"UPtr",0
,"UPtr",0)
Return pThumbnail
}
ConvertRGBtoHSL(R, G, B) {
SetFormat, float, 0.5
R := (R / 255)
G := (G / 255)
B := (B / 255)
Min     := min(R, G, B)
Max     := max(R, G, B)
del_Max := Max - Min
L := (Max + Min) / 2
if (del_Max = 0)
{
H := S := 0
} else
{
if (L < 0.5)
S := del_Max / (Max + Min)
else
S := del_Max / (2 - Max - Min)
del_R := (((Max - R) / 6) + (del_Max / 2)) / del_Max
del_G := (((Max - G) / 6) + (del_Max / 2)) / del_Max
del_B := (((Max - B) / 6) + (del_Max / 2)) / del_Max
if (R = Max)
{
H := del_B - del_G
} else
{
if (G = Max)
H := (1 / 3) + del_R - del_B
else if (B = Max)
H := (2 / 3) + del_G - del_R
}
if (H < 0)
H += 1
if (H > 1)
H -= 1
}
return [abs(round(h*360)), abs(s), abs(l)]
}
ConvertHSLtoRGB(H, S, L) {
H := H/360
if (S == 0)
{
R := L*255
G := L*255
B := L*255
} else
{
if (L < 0.5)
var_2 := L * (1 + S)
else
var_2 := (L + S) - (S * L)
var_1 := 2 * L - var_2
R := 255 * ConvertHueToRGB(var_1, var_2, H + (1 / 3))
G := 255 * ConvertHueToRGB(var_1, var_2, H)
B := 255 * ConvertHueToRGB(var_1, var_2, H - (1 / 3))
}
Return [round(R), round(G), round(B)]
}
ConvertHueToRGB(v1, v2, vH) {
vH := ((vH<0) ? ++vH : vH)
vH := ((vH>1) ? --vH : vH)
return  ((6 * vH) < 1) ? (v1 + (v2 - v1) * 6 * vH)
: ((2 * vH) < 1) ? (v2)
: ((3 * vH) < 2) ? (v1 + (v2 - v1) * ((2 / 3) - vH) * 6)
: v1
}
Gdip_ErrorHandler(errCode, throwErrorMsg, additionalInfo:="") {
Static errList := {1:"Generic_Error", 2:"Invalid_Parameter"
, 3:"Out_Of_Memory", 4:"Object_Busy"
, 5:"Insufficient_Buffer", 6:"Not_Implemented"
, 7:"Win32_Error", 8:"Wrong_State"
, 9:"Aborted", 10:"File_Not_Found"
, 11:"Value_Overflow", 12:"Access_Denied"
, 13:"Unknown_Image_Format", 14:"Font_Family_Not_Found"
, 15:"Font_Style_Not_Found", 16:"Not_TrueType_Font"
, 17:"Unsupported_GdiPlus_Version", 18:"Not_Initialized"
, 19:"Property_Not_Found", 20:"Property_Not_Supported"
, 21:"Profile_Not_Found", 100:"Unknown_Wrapper_Error"}
If !errCode
Return
aerrCode := (errCode<0) ? 100 : errCode
If errList.HasKey(aerrCode)
GdipErrMsg := "GDI+ ERROR: " errList[aerrCode]  " [CODE: " aerrCode "]" additionalInfo
Else
GdipErrMsg := "GDI+ UNKNOWN ERROR: " aerrCode additionalInfo
If (throwErrorMsg=1)
MsgBox, % GdipErrMsg
Return GdipErrMsg
}
