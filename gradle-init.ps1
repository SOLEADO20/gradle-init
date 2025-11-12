# Gradle项目镜像仓库初始化工具
# @Updated 2025-11-13 02:16
# @Created 2025-10-27 17:36
# @Author Kei
# @Version 1.0-stable


# ================================函数公共变量部分================================


# 可自定义的部分
$DEBUG_LEVEL=0                      # 自定义的调试级别 0 / 1 / 2
$IS_DEV_FEATURE_ENABLED=$false      # 是否启用开发期间的额外特性（以便定位问题），正式使用时请关闭
$DEBUG_PREFIX_FUNC_NAME="++ "       # 函数入口调试消息前缀-函数名
$DEBUG_PREFIX_PARAM="**** "         # 函数入口调试消息前缀-参数
$IS_WRAPPER_FILE_REQUIRED=$true     # 是否需要处理wrapper文件
$IS_SETTINGS_FILE_REQUIRED=$true    # 是否需要处理settings文件
$IS_BUILD_FILE_REQUIRED=$false      # 是否需要处理build文件（Android Studio默认只信任settings文件）
# 以下变量不要修改
$DEBUG_PREFERENCE="Continue"        # 确定PS如何响调试消息（仅初始化，后续由 $DEBUG_LEVEL 决定）
$IS_DEBUG_ON=$false                 # 是否启用调试（仅初始化，后续由 $DEBUG_LEVEL 决定）
# 全局化部分公共变量，方便访问
$Global:IS_DEV_FEATURE_ENABLED=$IS_DEV_FEATURE_ENABLED
# 根据调试级别决定PS的调试消息响应行为
switch ($DEBUG_LEVEL) {
    0 {
        $IS_DEBUG_ON=$false # 禁用调试
        $DEBUG_PREFERENCE="SilentlyContinue"    # 不会显示调试消息
    }
    1 {
        $IS_DEBUG_ON=$true  # 启用调试
        $DEBUG_PREFERENCE="Continue"            # 显示调试消息并继续执行（调试消息处，不暂停）
    }
    2 {
        $IS_DEBUG_ON=$true  # 启用调试
        $DEBUG_PREFERENCE="Inquire"             # 显示调试消息并询问是否继续（调试消息处，暂停）
    }
    Default {
        $IS_DEBUG_ON=$false # 禁用调试
        $DEBUG_PREFERENCE="SilentlyContinue"    # 不会显示调试消息
    }
}


# ================================类定义部分================================


# 定义类：替换项
class ReplacementItem {
    # 测试表达式（用于检查是否符合替换条件的正则表达式，不匹配则执行替换）
    [string]$TestExp
    # 查找表达式（捕获需要替换的内容）
    [string]$SearchExp
    # 替换表达式（捕获内容的替换表达）
    [string]$ReplaceExp
    # 测试描述（对测试表达式的描述）
    [string]$TestDesc

    # 哈希表参数构造方法
    ReplacementItem([hashtable]$Info) {
        # 根据传入的哈希表，快捷初始化相关属性
        switch ($Info.Keys) {
            'TestExp'       { $this.TestExp     = $Info.TestExp }
            'SearchExp'     { $this.SearchExp   = $Info.SearchExp }
            'ReplaceExp'    { $this.ReplaceExp  = $Info.ReplaceExp }
            'TestDesc'      { $this.TestDesc    = $Info.TestDesc }
        }
        # 若TestDesc未提供且未初始化，则初始化为与TestExp一致
        if ( !$Info.ContainsKey('TestDesc') -and !$this.TestDesc ) {
            $this.TestDesc=$this.TestExp
        }
        # 确保已提供TestDesc的情况下，以提供的值为准
        if ( $Info.ContainsKey('TestDesc') -and $this.TestDesc -ne $Info.TestDesc ) {
            $this.TestDesc=$Info.TestDesc
        }
    }

    # 无参构造方法
    ReplacementItem() {
        # Write-Host "调用无参构造方法。"
    }

    # 基本参数构造方法
    ReplacementItem([string]$TestExp, [string]$SearchExp, [string]$ReplaceExp) {
        $this.TestExp       = $TestExp
        $this.SearchExp     = $SearchExp
        $this.ReplaceExp    = $ReplaceExp
        $this.TestDesc      = $TestExp
    }
    
    # 完整参数构造方法
    ReplacementItem([string]$TestExp, [string]$SearchExp, [string]$ReplaceExp, [string]$TestDesc) {
        $this.TestExp       = $TestExp
        $this.SearchExp     = $SearchExp
        $this.ReplaceExp    = $ReplaceExp
        $this.TestDesc      = $TestDesc
    }
}


# 定义类：仓库替换项
class RepoReplacementItem : ReplacementItem {
    # 基础替换表达式
    # 测试表达式（用于检查是否符合替换条件的正则表达式，不匹配则执行替换）
    [string]$TestExp
    # 查找表达式（捕获需要替换的内容）
    [string]$SearchExp
    # 替换表达式（捕获内容的替换表达）
    [string]$ReplaceExp
    # 测试描述（对测试表达式的描述）
    [string]$TestDesc

    # 精准替换表达式
    # 测试表达式（用于进一步检查是否符合精准插入替换条件的正则表达式，不匹配则执行基础替换）
    [string]$TestExp_Orderly
    # 查找表达式（捕获需要替换的内容-有序版）
    [string]$SearchExp_Orderly
    # 替换表达式（捕获内容的替换表达-有序版）
    [string]$ReplaceExp_Orderly

    # 常用的子表达式
    # 如需匹配CRLF换行符（`r`n），且匹配末尾，请使用 "`r?`$`n" 的匹配表达式；此外，"\s" 和 "." 也能匹配 "`r"。
    static hidden [string]$REG_indent               = "(?<indent>^[\s]*)"
    static hidden [string]$REG_repoHead             = "(?<repoHead>repositories[\s]*\{[\s]*?`$`n)"
    static hidden [string]$REG_pluginHead           = "(?m)(?<pluginHead>^pluginManagement[\s]*\{[\s]*?`$`n)"
    static hidden [string]$REG_dependencyHead       = "(?m)(?<dependencyHead>^dependencyResolutionManagement[\s]*\{[\s]*?`$`n)"
    static hidden [string]$REG_rootRepoHead         = "(?m)(?<rootRepoHead>^$([RepoReplacementItem]::REG_repoHead))"
    static hidden [string]$REG_pluginRepoHead       = "(?<pluginRepoHead>$([RepoReplacementItem]::REG_pluginHead)(^[\s].*`$`n)*?$([RepoReplacementItem]::REG_indent)$([RepoReplacementItem]::REG_repoHead))"
    static hidden [string]$REG_dependencyRepoHead   = "(?<dependencyRepoHead>$([RepoReplacementItem]::REG_dependencyHead)(^[\s].*`$`n)*?$([RepoReplacementItem]::REG_indent)$([RepoReplacementItem]::REG_repoHead))"
    static hidden [string]$REG_pre                  = "(?<pre>([\s].*`n)*?)"
    
    # 定位用前缀
    static hidden [string]$LABEL_root_basic         = ""
    static hidden [string]$LABEL_root_orderly       = ""
    static hidden [string]$LABEL_plugin_basic       = ""
    static hidden [string]$LABEL_plugin_orderly     = ""
    static hidden [string]$LABEL_dependency_basic   = ""
    static hidden [string]$LABEL_dependency_orderly = ""

    # 字符串转义方法
    static hidden [string]ToReg([string]$str) {
        # 所有需要转义的字符有 [().\^$|?*+{
        return $str -replace '\(','\(' -replace '\)','\)' -replace '\{','\{' -replace '\.','\.'
    }

    # 设置定位用前缀（仅供调试）
    static hidden [void]SetReplacePrefix() {
        [RepoReplacementItem]::LABEL_root_basic         = "// rrrr`n"
        [RepoReplacementItem]::LABEL_root_orderly       = "// rrrr_`n"
        [RepoReplacementItem]::LABEL_plugin_basic       = "// PPPP`n"
        [RepoReplacementItem]::LABEL_plugin_orderly     = "// PPPP_`n"
        [RepoReplacementItem]::LABEL_dependency_basic   = "// DDDD`n"
        [RepoReplacementItem]::LABEL_dependency_orderly = "// DDDD_`n"
    }

    # 哈希表参数构造方法
    RepoReplacementItem([hashtable]$Info) {
        if ($Global:IS_DEV_FEATURE_ENABLED) {
            [RepoReplacementItem]::SetReplacePrefix()
        }

        if ( $Info.ContainsKey('scope') -or $Info.ContainsKey('type') -or $Info.ContainsKey('value') -or $Info.ContainsKey('nextValue') ) {
            if ( !($Info.ContainsKey('scope') -and $Info.ContainsKey('type') -and $Info.ContainsKey('value') -or $Info.ContainsKey('nextValue')) ) {
                Write-Error "仓库替换项创建失败。（键名不符合要求）"
                return
            }
            $SearchTable=@{
                # scope
                root=@{
                    TestDesc      = "repositories -> {0}"
                    # 基础替换表达式
                    TestExp       = "$([RepoReplacementItem]::REG_rootRepoHead)$([RepoReplacementItem]::REG_pre)([\s]*{0}[\s]*`n)"
                    SearchExp     = "$([RepoReplacementItem]::REG_rootRepoHead)"
                    ReplaceExp    = "$([RepoReplacementItem]::LABEL_root_basic)`${rootRepoHead}    {0}`n"
                    # 精准替换表达式
                    TestExp_Orderly       = "$([RepoReplacementItem]::REG_rootRepoHead)$([RepoReplacementItem]::REG_pre)(?<next>.*{0}.*`n)"
                    SearchExp_Orderly     = "$([RepoReplacementItem]::REG_rootRepoHead)$([RepoReplacementItem]::REG_pre)(?<next>.*{0}.*`n)"
                    ReplaceExp_Orderly    = "$([RepoReplacementItem]::LABEL_root_orderly)`${rootRepoHead}`${pre}    {0}`n`${next}"
                }
                plugin=@{
                    TestDesc      = "pluginManagement -> repositories -> {0}"
                    # 基础替换表达式
                    TestExp       = "$([RepoReplacementItem]::REG_pluginRepoHead)$([RepoReplacementItem]::REG_pre)([\s]*{0}[\s]*`n)"
                    SearchExp     = "$([RepoReplacementItem]::REG_pluginRepoHead)"
                    ReplaceExp    = "$([RepoReplacementItem]::LABEL_plugin_basic)`${pluginRepoHead}`${indent}`${indent}{0}`n"
                    # 精准替换表达式
                    TestExp_Orderly       = "$([RepoReplacementItem]::REG_pluginRepoHead)$([RepoReplacementItem]::REG_pre)(?<next>.*{0}.*`n)"
                    SearchExp_Orderly     = "$([RepoReplacementItem]::REG_pluginRepoHead)$([RepoReplacementItem]::REG_pre)(?<next>.*{0}.*`n)"
                    ReplaceExp_Orderly    = "$([RepoReplacementItem]::LABEL_plugin_orderly)`${pluginRepoHead}`${pre}`${indent}`${indent}{0}`n`${next}"
                }
                dependency=@{
                    TestDesc      = "dependencyResolutionManagement -> repositories -> {0}"
                    # 基础替换表达式
                    TestExp       = "$([RepoReplacementItem]::REG_dependencyRepoHead)$([RepoReplacementItem]::REG_pre)([\s]*{0}[\s]*`n)"
                    SearchExp     = "$([RepoReplacementItem]::REG_dependencyRepoHead)"
                    ReplaceExp    = "$([RepoReplacementItem]::LABEL_dependency_basic)`${dependencyRepoHead}`${indent}`${indent}{0}`n"
                    # 精准替换表达式
                    TestExp_Orderly       = "$([RepoReplacementItem]::REG_dependencyRepoHead)$([RepoReplacementItem]::REG_pre)(?<next>.*{0}.*`n)"
                    SearchExp_Orderly     = "$([RepoReplacementItem]::REG_dependencyRepoHead)$([RepoReplacementItem]::REG_pre)(?<next>.*{0}.*`n)"
                    ReplaceExp_Orderly    = "$([RepoReplacementItem]::LABEL_dependency_orderly)`${dependencyRepoHead}`${pre}`${indent}`${indent}{0}`n`${next}"
                }
            }
            $matchedExp=$SearchTable[$Info.scope]
            # 初始化仓库、下一仓库，及其匹配表达式
            $repo           =$Info.value
            $nextRepo       =$Info.nextValue
            $repo_reg       =$([RepoReplacementItem]::ToReg($repo))
            $nextRepo_reg   =$([RepoReplacementItem]::ToReg($nextRepo))
            # 兼容、适配URL，使其转换成标准的仓库格式
            if ($Info.type -eq 'RepoUrl') {
                $repo       ="maven { url '$repo' }"
                $repo_reg   ="maven[\s]*\{[\s]*url[\s]+['`"]$repo_reg['`"][\s]*}"
            }
            # 拼装合成各表达式（`$Info.TestDesc=$matchedExp.TestDesc -f $repo` 的形式用不了，输入字符串还要求格式，正则表达式容易被误当成格式，进而导致错误）
            # 描述表达式
            $Info.TestDesc=$matchedExp.TestDesc -replace '\{0}', $repo
            # 基础替换表达式
            $Info.TestExp=$matchedExp.TestExp -replace '\{0}', $repo_reg
            $Info.SearchExp=$matchedExp.SearchExp
            $Info.ReplaceExp=$matchedExp.ReplaceExp -replace '\{0}', $repo
            # 精准替换表达式
            $Info.TestExp_Orderly=$matchedExp.TestExp_Orderly -replace '\{0}', $nextRepo_reg
            $Info.SearchExp_Orderly=$matchedExp.SearchExp_Orderly -replace '\{0}', $nextRepo_reg
            $Info.ReplaceExp_Orderly=$matchedExp.ReplaceExp_Orderly -replace '\{0}', $repo
        }


        # 根据传入的哈希表，快捷初始化相关属性
        switch ($Info.Keys) {
            'TestDesc'      { $this.TestDesc    = $Info.TestDesc }
            'TestExp'       { $this.TestExp     = $Info.TestExp }
            'SearchExp'     { $this.SearchExp   = $Info.SearchExp }
            'ReplaceExp'    { $this.ReplaceExp  = $Info.ReplaceExp }
            'TestExp_Orderly'       { $this.TestExp_Orderly     = $Info.TestExp_Orderly }
            'SearchExp_Orderly'     { $this.SearchExp_Orderly   = $Info.SearchExp_Orderly }
            'ReplaceExp_Orderly'    { $this.ReplaceExp_Orderly  = $Info.ReplaceExp_Orderly }
        }
        # 若TestDesc未提供且未初始化，则初始化为与TestExp一致
        if ( !$Info.ContainsKey('TestDesc') -and !$this.TestDesc ) {
            $this.TestDesc=$this.TestExp
        }
        # 确保已提供TestDesc的情况下，以提供的值为准
        if ( $Info.ContainsKey('TestDesc') -and $this.TestDesc -ne $Info.TestDesc ) {
            $this.TestDesc=$Info.TestDesc
        }
    }

    # 基本参数构造方法
    RepoReplacementItem([string]$TestExp, [string]$SearchExp, [string]$ReplaceExp) {
        $this.TestExp       = $TestExp
        $this.SearchExp     = $SearchExp
        $this.ReplaceExp    = $ReplaceExp
        $this.TestDesc      = $TestExp
    }

    # 完整参数构造方法（不含精准替换表达式）
    RepoReplacementItem([string]$TestExp, [string]$SearchExp, [string]$ReplaceExp, [string]$TestDesc) {
        $this.TestExp       = $TestExp
        $this.SearchExp     = $SearchExp
        $this.ReplaceExp    = $ReplaceExp
        $this.TestDesc      = $TestDesc
    }

    # 完整参数构造方法（含精准替换表达式）
    RepoReplacementItem([string]$TestExp, [string]$SearchExp, [string]$ReplaceExp, [string]$TestDesc, [string]$TestExp_Orderly, [string]$SearchExp_Orderly, [string]$ReplaceExp_Orderly) {
        $this.TestExp       = $TestExp
        $this.SearchExp     = $SearchExp
        $this.ReplaceExp    = $ReplaceExp
        $this.TestDesc      = $TestDesc
        $this.TestExp_Orderly       = $TestExp_Orderly
        $this.SearchExp_Orderly     = $SearchExp_Orderly
        $this.ReplaceExp_Orderly    = $ReplaceExp_Orderly
    }
}


# ================================函数定义部分================================


# 备份文件，并默认根据时间戳命名
function Backup-File {
    # 参数设定
    [CmdletBinding()]
    param (
        # 源文件路径
        [Parameter(Mandatory=$true)]
        [string]$SrcFilePath,
        # 备份文件路径（非必须）
        [string]$BakFilePath
    )
    # 参数打印（仅供调试）
    $DebugPreference = "$DEBUG_PREFERENCE"
    if ($MyInvocation.BoundParameters['Debug']) {
        Write-Debug "${DEBUG_PREFIX_FUNC_NAME}访问：$($MyInvocation.MyCommand.Name)"
        foreach ($key in $MyInvocation.BoundParameters.keys) {
            if ($key -ne 'Debug') {
                Write-Debug "${DEBUG_PREFIX_PARAM}参数：${key}='$($MyInvocation.BoundParameters[$key])'"
            }
        }
    }
    # 设置备份文件默认路径
    if (!$BakFilePath) {
        $file_timestamp=(Get-Item "$SrcFilePath").LastWriteTime | Get-Date -Format 'yyyyMMdd_HHmmss'
        $BakFilePath="${SrcFilePath}.BAK_${file_timestamp}"
    }
    # 检查文件是否存在
    if ( !(Test-Path -Path $SrcFilePath -PathType Leaf) ) {
        Write-Warning "文件 '$SrcFilePath' 不存在！退出..."
        return $false
    }
    # 防止文件被丢进一个已存在的文件夹中
    if ( Test-Path -Path $BakFilePath ) {
        Write-Warning "备份文件 '$SrcFilePath' -> '$BakFilePath' 过程中出现问题！（目标路径已被其他文件（夹）使用）退出..."
        return $false
    }
    # 生成备份文件
    Copy-Item -Path "$SrcFilePath" -Destination "$BakFilePath" -Force
    # 复制文件时间属性
    $(Get-Item "$BakFilePath").CreationTime=$(Get-Item "$SrcFilePath").CreationTime
    $(Get-Item "$BakFilePath").LastWriteTime=$(Get-Item "$SrcFilePath").LastWriteTime
    $(Get-Item "$BakFilePath").LastAccessTime=$(Get-Date)
    # 检查文件是否存在
    if ( !((Test-Path -Path $BakFilePath -PathType Leaf) -and (Test-Path -Path $SrcFilePath -PathType Leaf)) ) {
        Write-Warning "备份文件 '$SrcFilePath' -> '$BakFilePath' 过程中出现问题！（文件创建失败）退出..."
        return $false
    }
    # 校验文件哈希
    if ( $(Get-FileHash -Path $BakFilePath -Algorithm SHA256).Hash -ne $(Get-FileHash -Path $SrcFilePath -Algorithm SHA256).Hash ) {
        Write-Warning "备份文件 '$SrcFilePath' -> '$BakFilePath' 过程中出现问题！（文件哈希不一致）退出..."
        return $false
    }
    Write-Host "生成备份文件: '$BakFilePath'"
    return "$BakFilePath"
}


# 查询文件差异
function Show-Diff {
    # 参数设定
    [CmdletBinding()]
    param (
        # 旧文件路径
        [Parameter(Mandatory=$true)]
        [string]$OldFilePath,
        # 新文件路径
        [Parameter(Mandatory=$true)]
        [string]$NewFilePath
    )
    # 参数打印（仅供调试）
    $DebugPreference = "$DEBUG_PREFERENCE"
    if ($MyInvocation.BoundParameters['Debug']) {
        Write-Debug "${DEBUG_PREFIX_FUNC_NAME}访问：$($MyInvocation.MyCommand.Name)"
        foreach ($key in $MyInvocation.BoundParameters.keys) {
            if ($key -ne 'Debug') {
                Write-Debug "${DEBUG_PREFIX_PARAM}参数：${key}='$($MyInvocation.BoundParameters[$key])'"
            }
        }
    }
    # 检查文件是否存在
    if ( !(Test-Path -Path $OldFilePath -PathType Leaf) ) {
        Write-Warning "文件 '$OldFilePath' 不存在！退出..."
        return $false
    } elseif ( !(Test-Path -Path $NewFilePath -PathType Leaf) ) {
        Write-Warning "文件 '$NewFilePath' 不存在！退出..."
        return $false
    }
    # 获取文件内容
    $old_file_content=Get-Content -Path $OldFilePath
    $new_file_content=Get-Content -Path $NewFilePath
    # 当文件无任何内容时，Get-Content将返回空值。为防止造成不必要的影响，要避免它。
    if ($null -eq $old_file_content) {
        $old_file_content=""
    }
    if ($null -eq $new_file_content) {
        $new_file_content=""
    }
    # 查询文件差异
    # TODO 自己实现一套差异显示功能（这个PS自带的差异显示效果不太行，重点是它给的差异结果不一定按照内容的顺序来）
    $diffRes=Compare-Object -ReferenceObject $old_file_content -DifferenceObject $new_file_content
    if ($diffRes) {
        Write-Host "文件 '$OldFilePath' -> '$NewFilePath' 的差异如下: "
        Write-Host '----------------------------------------------------------------'
        # 仿Git风格
        $diffRes | ForEach-Object {
            $color = if ($_.SideIndicator -eq '=>') { 'Green' } else { 'Red' }
            $symbol = if ($_.SideIndicator -eq '=>') { '+' } else { '-' }
            Write-Host -ForegroundColor $color "$symbol $($_.InputObject)"
        }
    } else {
        Write-Host "文件 '$OldFilePath' -> '$NewFilePath' 无差异。"
        return $false
    }
    return $true
}


# 批量替换文本
function ReplaceStrBatch {
    # 参数设定
    [CmdletBinding()]
    param (
        # 输入内容
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [System.Object]$Value,
        # 替换项信息
        [Parameter(Mandatory=$true)]
        [ReplacementItem[]]$ReplacementItemList
    )
    # 参数打印（仅供调试）
    $DebugPreference = "$DEBUG_PREFERENCE"
    if ($MyInvocation.BoundParameters['Debug']) {
        Write-Debug "${DEBUG_PREFIX_FUNC_NAME}访问：$($MyInvocation.MyCommand.Name)"
        foreach ($key in $MyInvocation.BoundParameters.keys) {
            if ($key -ne 'Debug') {
                Write-Debug "${DEBUG_PREFIX_PARAM}参数：${key}='$($MyInvocation.BoundParameters[$key])'"
            }
        }
    }
    # 当文件无任何内容时，Get-Content将返回空值。当传入空值时，替换操作将无法成功执行。为防止造成不必要的影响，要避免它。
    if ($null -eq $Value) {
        $Value=""
        Write-Warning "目标文件内容为空。"
    }
    # 替换次数计数
    $num=0
    $num_orderly=0
    # 遍历替换项信息，逐个替换
    foreach ($replacementItem in $ReplacementItemList) {
        if ( $Value -match $replacementItem.TestExp ) {
            Write-Warning "目标文件已包含所需内容 '$($replacementItem.TestDesc)'。"
        }else {
            if ( $replacementItem.TestExp_Orderly -and $Value -match $replacementItem.TestExp_Orderly ) {
                $Value=$Value -replace $replacementItem.SearchExp_Orderly, $replacementItem.ReplaceExp_Orderly
                $num_orderly++
            } else {
                Write-Warning "替换项 '$($replacementItem.TestDesc)' 的具体插入点未定义或目标文件内容不与之匹配，将仅对其执行基础替换。"
                $Value=$Value -replace $replacementItem.SearchExp, $replacementItem.ReplaceExp
            }
            $num++
        }
    }
    Write-Host "已准备好进行共 $num 次替换，含 $num_orderly 次精准替换。"
    return $Value
}


# 一站式处理文件
function HandleFileBatch {
    # 参数设定
    [CmdletBinding()]
    param (
        # 输入文件路径
        [Parameter(Mandatory=$true)]
        [string]$InFilePath,
        # 替换项信息
        [Parameter(Mandatory=$true)]
        [ReplacementItem[]]$ReplacementItemList
    )
    # 参数打印（仅供调试）
    $DebugPreference = "$DEBUG_PREFERENCE"
    if ($MyInvocation.BoundParameters['Debug']) {
        Write-Debug "${DEBUG_PREFIX_FUNC_NAME}访问：$($MyInvocation.MyCommand.Name)"
        foreach ($key in $MyInvocation.BoundParameters.keys) {
            if ($key -ne 'Debug') {
                Write-Debug "${DEBUG_PREFIX_PARAM}参数：${key}='$($MyInvocation.BoundParameters[$key])'"
            }
        }
    }
    # 反转数组中的元素，使得优先从“老末”开始处理，确保仓库的插入顺序无误
    [array]::Reverse($ReplacementItemList)
    # 初始化返回值
    $status=$true
    # 检查文件是否存在
    if ( !(Test-Path -Path $InFilePath -PathType Leaf) ) {
        Write-Warning "文件 '$InFilePath' 不存在！退出..."
        return 1
    }
    # 开始处理
    Write-Host "`n处理文件 '$InFilePath'..."
    Write-Host "╔══════════════════════════════════════════════════════════════╗"
    # 获取文件内容
    $in_file_content=Get-Content -Path $InFilePath -Raw
    # 获取替换后的文件内容
    $out_file_content=$in_file_content | ReplaceStrBatch -ReplacementItemList $ReplacementItemList -Debug:$MyInvocation.BoundParameters['Debug']
    # 检查文件内容是否存在实际更改
    if ($out_file_content -cne $in_file_content) {
        # 文件内容已更改，依次进行：文件备份、新内容写入、差异显示
        # 备份文件
        if ( $bak_file=Backup-File -SrcFilePath "$InFilePath" -Debug:$MyInvocation.BoundParameters['Debug'] ) {
            # 写入新内容
            Write-Host "写入新内容至: '$InFilePath'"
            $out_file_content | Set-Content -Path $InFilePath -NoNewline
            # 显示文件差异
            $null=Show-Diff -OldFilePath "$bak_file" -NewFilePath "$InFilePath" -Debug:$MyInvocation.BoundParameters['Debug']
        } else {
            Write-Warning "处理文件 '$InFilePath' 时出现问题。操作取消..."
            $status=$false
        }
    } else {
        # 文件内容未更改，不做任何处理
        Write-Warning "跳过对文件 '$InFilePath' 的处理。（无实际可用的更改）"
        $status=$false
    }
    Write-Host "╚══════════════════════════════════════════════════════════════╝"
    return $status
}


# 生成有序的仓库替换项列表（数组）
function Get-RepoReplacementItemList {
    # 参数设定
    [CmdletBinding()]
    param (
        # 仓库列表
        [Parameter(Mandatory=$true)]
        [hashtable[]]$RepoList,
        # 是否强制使用LF换行符
        [Parameter(Mandatory=$true)]
        [bool]$ForceLF
    )
    # 参数打印（仅供调试）
    $DebugPreference = "$DEBUG_PREFERENCE"
    if ($MyInvocation.BoundParameters['Debug']) {
        Write-Debug "${DEBUG_PREFIX_FUNC_NAME}访问：$($MyInvocation.MyCommand.Name)"
        foreach ($key in $MyInvocation.BoundParameters.keys) {
            if ($key -ne 'Debug') {
                Write-Debug "${DEBUG_PREFIX_PARAM}参数：${key}='$($MyInvocation.BoundParameters[$key])'"
            }
        }
    }
    # 生成仓库替换项列表
    # 元素类型是确定的，尽量使用泛型List，而不要使用ArrayList
    # 另外，调用ArrayList的Add方法时，会返回元素索引到标准输出，如果忘记对其显式捕获，则它会混入函数返回值中，造成一系列问题。
    # 而泛型List的Add方法没有返回值，也就不用担心这个问题。
    # $List=[System.Collections.ArrayList]::new()
    $List=[System.Collections.Generic.List[ReplacementItem]]::new()
    # 记录所有的仓库所属
    $RepoScope=@{ root=$false; plugin=$false; dependency=$false }
    # 添加仓库
    # 对仓库按作用域scope进行分拣
    $RepoList_root          = [System.Collections.Generic.List[hashtable]]::new()
    $RepoList_plugin        = [System.Collections.Generic.List[hashtable]]::new()
    $RepoList_dependency    = [System.Collections.Generic.List[hashtable]]::new()
    for ($i = 0; $i -lt $RepoList.Count; $i++) {
        switch ($RepoList[$i].scope) {
            'root'          {
                $RepoScope.root=$true
                [void]$RepoList_root.Add($RepoList[$i])
                break
            }
            'plugin'        {
                $RepoScope.plugin=$true
                [void]$RepoList_plugin.Add($RepoList[$i])
                break
            }
            'dependency'    {
                $RepoScope.dependency=$true
                [void]$RepoList_dependency.Add($RepoList[$i])
                break
            }
            Default         {
                Write-Error "处理插件仓库哈希表数组 'RepoList[$i]' 时出现问题。（键名scope不符合要求）操作取消..."
                return $false
            }
        }
    }
    # 对各scope仓库进行处理
    for ($i = 0; $i -lt $RepoList_root.Count-1; $i++) {
        [void]$List.Add(
            [RepoReplacementItem]::new(@{
                scope=$RepoList_root[$i].scope
                type=$RepoList_root[$i].type
                value=$RepoList_root[$i].value
                nextValue=$RepoList_root[$i+1].value
            })
        )
    }
    for ($i = 0; $i -lt $RepoList_plugin.Count-1; $i++) {
        [void]$List.Add(
            [RepoReplacementItem]::new(@{
                scope=$RepoList_plugin[$i].scope
                type=$RepoList_plugin[$i].type
                value=$RepoList_plugin[$i].value
                nextValue=$RepoList_plugin[$i+1].value
            })
        )
    }
    for ($i = 0; $i -lt $RepoList_dependency.Count-1; $i++) {
        [void]$List.Add(
            [RepoReplacementItem]::new(@{
                scope=$RepoList_dependency[$i].scope
                type=$RepoList_dependency[$i].type
                value=$RepoList_dependency[$i].value
                nextValue=$RepoList_dependency[$i+1].value
            })
        )
    }
    # 确保各scope“仓库所属”结构存在
    if ($RepoScope.root) {
        # 根下追加repositories
        [void]$List.Add(
            [RepoReplacementItem]::new(@{
                TestDesc      = "repositories"
                # 基础替换表达式
                TestExp       = "$([RepoReplacementItem]::REG_rootRepoHead)"
                SearchExp     = "(?s)(?=\z)"
                ReplaceExp    = "`n// Define root repo`nrepositories {`n}"
            })
        )
    }
    if ($RepoScope.plugin) {
        # pluginManagement下追加repositories
        [void]$List.Add(
            [RepoReplacementItem]::new(@{
                TestDesc      = "pluginManagement -> repositories"
                # 基础替换表达式
                TestExp       = "$([RepoReplacementItem]::REG_pluginRepoHead)"
                SearchExp     = "$([RepoReplacementItem]::REG_pluginHead)"
                ReplaceExp    = "`${pluginHead}    // Define plugin repo`n    repositories {`n    }`n"
            })
        )
        # 根下追加pluginManagement
        [void]$List.Add(
            [RepoReplacementItem]::new(@{
                TestDesc      = "pluginManagement"
                # 基础替换表达式
                TestExp       = "$([RepoReplacementItem]::REG_pluginHead)"
                SearchExp     = "(?s)(?=\z)"
                ReplaceExp    = "`n// New pluginManagement`npluginManagement {`n}"
            })
        )
    }
    if ($RepoScope.dependency) {
        # dependencyResolutionManagement下追加repositories
        [void]$List.Add(
            [RepoReplacementItem]::new(@{
                TestDesc      = "dependencyResolutionManagement -> repositories"
                # 基础替换表达式
                TestExp       = "$([RepoReplacementItem]::REG_dependencyRepoHead)"
                SearchExp     = "$([RepoReplacementItem]::REG_dependencyHead)"
                ReplaceExp    = "`${dependencyHead}    // Define dependency repo`n    repositories {`n    }`n"
            })
        )
        # 根下追加dependencyResolutionManagement
        [void]$List.Add(
            [RepoReplacementItem]::new(@{
                TestDesc      = "dependencyResolutionManagement"
                # 基础替换表达式
                TestExp       = "$([RepoReplacementItem]::REG_dependencyHead)"
                SearchExp     = "(?s)(?=\z)"
                ReplaceExp    = "`n// New dependencyResolutionManagement`ndependencyResolutionManagement {`n}"
            })
        )
    }
    if ($ForceLF) {
        # 强制转换CRLF换行符为LF换行符
        [void]$List.Add(
            [RepoReplacementItem]::new(@{
                TestDesc      = "（强制使用LF换行符）"
                # 基础替换表达式
                TestExp       = "\A.\A"
                SearchExp     = "`r`n"
                ReplaceExp    = "`n"
            })
        )
    }
    return $List.ToArray()
}


# ================================替换内容定义部分================================


if ($IS_DEV_FEATURE_ENABLED) {
    Write-Host "访问Gradle仓库处理脚本（0）。`n"
} else {
    Write-Host "欢迎使用Gradle仓库处理脚本！`n借助此脚本，你可以在Gradle项目中快速插入国内镜像仓库（暂不适用于Kotlin）。`n"
}


# ****************文件变量定义****************
# wrapper配置文件
$GRADLE_WRAPPER_PROP_FILE=".\gradle\wrapper\gradle-wrapper.properties"
# settings文件
$GRADLE_SETTINGS_FILE=".\settings.gradle"
# build文件
$GRADLE_BUILD_FILE=".\build.gradle"
# 测试文件
$TEST_FILE=""
# 开发期间专用设置
if ($IS_DEV_FEATURE_ENABLED) {
    $GRADLE_WRAPPER_PROP_FILE=".\gradle-wrapper.properties"
    $GRADLE_SETTINGS_FILE=".\settings.gradle"
    $GRADLE_BUILD_FILE=".\build.gradle"
    $TEST_FILE=".\test.gradle"
}
# ****************仓库变量定义****************
# Gradle本体分发源
$GRADLE_BIN_REPO_OFFICIAL="//services.gradle.org/distributions/"    # //services.gradle.org/distributions/gradle-8.13-bin.zip
$GRADLE_BIN_REPO_TENCENT="//mirrors.cloud.tencent.com/gradle/"      # //mirrors.cloud.tencent.com/gradle/gradle-8.13-bin.zip
# 仓库镜像
# 阿里系的仓库很多文件找不到，会造成大量重试，浪费时间和资源，建议不要将阿里系的仓库置于首位。
# 阿里系仓库
$REPO_ALI_PUBLIC='https://maven.aliyun.com/repository/public'
$REPO_ALI_CENTRAL='https://maven.aliyun.com/repository/central'
$REPO_ALI_GOOGLE='https://maven.aliyun.com/repository/google'
$REPO_ALI_JCENTER='https://maven.aliyun.com/repository/jcenter'
$REPO_ALI_SPRING='https://maven.aliyun.com/repository/spring'
$REPO_ALI_SPRING_PLUGIN='https://maven.aliyun.com/repository/spring-plugin'
$REPO_ALI_GRADLE_PLUGIN='https://maven.aliyun.com/repository/gradle-plugin'
# 腾讯系仓库
$REPO_TENCENT_PUBLIC='https://mirrors.cloud.tencent.com/nexus/repository/maven-public'
# 华为系仓库
$REPO_HUAWEI_PUBLIC='https://mirrors.huaweicloud.com/repository/maven'
# 本地仓库
$REPO_LOCAL='mavenLocal()'
# ****************定义要替换的内容****************
# gradle-wrapper.properties配置文件的替换项
$WrapperReplacementItemList=@([ReplacementItem]::new(@{
    TestExp=[regex]::Escape($GRADLE_BIN_REPO_TENCENT)
    SearchExp=[regex]::Escape($GRADLE_BIN_REPO_OFFICIAL)
    ReplaceExp=$GRADLE_BIN_REPO_TENCENT
    TestDesc=$GRADLE_BIN_REPO_TENCENT
}))
# settings.gradle文件中要插入的仓库（按预期的插入先后顺序依次排列）
$SettingsRepoList=@(
    # 插件仓库
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_TENCENT_PUBLIC },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_HUAWEI_PUBLIC },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_ALI_PUBLIC },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_ALI_CENTRAL },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_ALI_GOOGLE },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_ALI_JCENTER },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_ALI_SPRING },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_ALI_GRADLE_PLUGIN },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_ALI_SPRING_PLUGIN },
    @{ scope='plugin';      type='Repo';    value=$REPO_LOCAL },
    # 依赖仓库
    @{ scope='dependency';  type='RepoUrl'; value=$REPO_TENCENT_PUBLIC },
    @{ scope='dependency';  type='RepoUrl'; value=$REPO_HUAWEI_PUBLIC },
    @{ scope='dependency';  type='RepoUrl'; value=$REPO_ALI_PUBLIC },
    @{ scope='dependency';  type='RepoUrl'; value=$REPO_ALI_CENTRAL },
    @{ scope='dependency';  type='RepoUrl'; value=$REPO_ALI_GOOGLE },
    @{ scope='dependency';  type='RepoUrl'; value=$REPO_ALI_JCENTER },
    @{ scope='dependency';  type='RepoUrl'; value=$REPO_ALI_SPRING },
    # @{ scope='dependency';  type='RepoUrl'; value=$REPO_ALI_GRADLE_PLUGIN },
    # @{ scope='dependency';  type='RepoUrl'; value=$REPO_ALI_SPRING_PLUGIN },
    @{ scope='dependency';  type='Repo';    value=$REPO_LOCAL },
    # 各scope最后一项仅用于定位插入点，不会被实际添加到文件，请勿删除
    @{ scope='plugin';      type='Repo';    value="google[\s({]" }, # 左圆括号、左花括号将被自动转义
    @{ scope='dependency';  type='Repo';    value="google[\s({]" } # 左圆括号、左花括号将被自动转义
)
# build.gradle文件中要插入的仓库（按预期的插入先后顺序依次排列）
$BuildRepoList=@(
    # 根仓库
    @{ scope='root';        type='RepoUrl'; value=$REPO_TENCENT_PUBLIC },
    @{ scope='root';        type='RepoUrl'; value=$REPO_HUAWEI_PUBLIC },
    @{ scope='root';        type='RepoUrl'; value=$REPO_ALI_PUBLIC },
    @{ scope='root';        type='RepoUrl'; value=$REPO_ALI_CENTRAL },
    @{ scope='root';        type='RepoUrl'; value=$REPO_ALI_GOOGLE },
    @{ scope='root';        type='RepoUrl'; value=$REPO_ALI_JCENTER },
    @{ scope='root';        type='RepoUrl'; value=$REPO_ALI_SPRING },
    @{ scope='root';        type='RepoUrl'; value=$REPO_ALI_GRADLE_PLUGIN },
    @{ scope='root';        type='RepoUrl'; value=$REPO_ALI_SPRING_PLUGIN },
    @{ scope='root';        type='Repo';    value=$REPO_LOCAL },
    # 各scope最后一项仅用于定位插入点，不会被实际添加到文件，请勿删除
    @{ scope='root';        type='Repo';    value="google[\s({]" } # 左圆括号、左花括号将被自动转义
)
# 测试文件中要插入的仓库（按预期的插入先后顺序依次排列）
$TestRepoList=@(
    # 根仓库
    @{ scope='root';        type='RepoUrl'; value=$REPO_TENCENT_PUBLIC },
    @{ scope='root';        type='RepoUrl'; value=$REPO_HUAWEI_PUBLIC },
    @{ scope='root';        type='RepoUrl'; value=$REPO_ALI_PUBLIC },
    @{ scope='root';        type='RepoUrl'; value=$REPO_ALI_CENTRAL },
    @{ scope='root';        type='RepoUrl'; value=$REPO_ALI_GOOGLE },
    @{ scope='root';        type='RepoUrl'; value=$REPO_ALI_JCENTER },
    @{ scope='root';        type='RepoUrl'; value=$REPO_ALI_SPRING },
    @{ scope='root';        type='RepoUrl'; value=$REPO_ALI_GRADLE_PLUGIN },
    @{ scope='root';        type='RepoUrl'; value=$REPO_ALI_SPRING_PLUGIN },
    @{ scope='root';        type='Repo';    value=$REPO_LOCAL },
    # 插件仓库
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_TENCENT_PUBLIC },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_HUAWEI_PUBLIC },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_ALI_PUBLIC },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_ALI_CENTRAL },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_ALI_GOOGLE },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_ALI_JCENTER },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_ALI_SPRING },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_ALI_GRADLE_PLUGIN },
    @{ scope='plugin';      type='RepoUrl'; value=$REPO_ALI_SPRING_PLUGIN },
    @{ scope='plugin';      type='Repo';    value=$REPO_LOCAL },
    # 依赖仓库
    @{ scope='dependency';  type='RepoUrl'; value=$REPO_TENCENT_PUBLIC },
    @{ scope='dependency';  type='RepoUrl'; value=$REPO_HUAWEI_PUBLIC },
    @{ scope='dependency';  type='RepoUrl'; value=$REPO_ALI_PUBLIC },
    @{ scope='dependency';  type='RepoUrl'; value=$REPO_ALI_CENTRAL },
    @{ scope='dependency';  type='RepoUrl'; value=$REPO_ALI_GOOGLE },
    @{ scope='dependency';  type='RepoUrl'; value=$REPO_ALI_JCENTER },
    @{ scope='dependency';  type='RepoUrl'; value=$REPO_ALI_SPRING },
    # @{ scope='dependency';  type='RepoUrl'; value=$REPO_ALI_GRADLE_PLUGIN },
    # @{ scope='dependency';  type='RepoUrl'; value=$REPO_ALI_SPRING_PLUGIN },
    @{ scope='dependency';  type='Repo';    value=$REPO_LOCAL },
    # 各scope最后一项仅用于定位插入点，不会被实际添加到文件，请勿删除
    @{ scope='root';        type='Repo';    value="google[\s({]" }, # 左圆括号、左花括号将被自动转义
    @{ scope='plugin';      type='Repo';    value="google[\s({]" }, # 左圆括号、左花括号将被自动转义
    @{ scope='dependency';  type='Repo';    value="google[\s({]" } # 左圆括号、左花括号将被自动转义
)
# 生成有序的仓库替换项列表
$RepoReplacementItemList_Settings   = Get-RepoReplacementItemList -RepoList $SettingsRepoList -ForceLF:$false -Debug:$IS_DEBUG_ON
$RepoReplacementItemList_Build      = Get-RepoReplacementItemList -RepoList $BuildRepoList -ForceLF:$false -Debug:$IS_DEBUG_ON
$RepoReplacementItemList_Test       = Get-RepoReplacementItemList -RepoList $TestRepoList -ForceLF:$false -Debug:$IS_DEBUG_ON


# ================================正式调用部分================================


# 对wrapper配置文件执行替换
if ($IS_WRAPPER_FILE_REQUIRED) {
    if ($WrapperReplacementItemList) {
        $null=HandleFileBatch -InFile "$GRADLE_WRAPPER_PROP_FILE" -ReplacementItemList $WrapperReplacementItemList -Debug:$IS_DEBUG_ON
    } else {
        Write-Warning "对文件 '$GRADLE_WRAPPER_PROP_FILE' 的操作无法执行。（无有效替换项列表）"
    }
}


# 对项目中的settings.gradle文件执行替换
if ($IS_SETTINGS_FILE_REQUIRED) {
    if ($RepoReplacementItemList_Settings) {
        $null=HandleFileBatch -InFile "$GRADLE_SETTINGS_FILE" -ReplacementItemList $RepoReplacementItemList_Settings -Debug:$IS_DEBUG_ON
    } else {
        Write-Warning "对文件 '$GRADLE_SETTINGS_FILE' 的操作无法执行。（无有效仓库列表）"
    }
}


# 对项目中的build.gradle文件执行替换
if ($IS_BUILD_FILE_REQUIRED) {
    if ($RepoReplacementItemList_Build) {
        $null=HandleFileBatch -InFile "$GRADLE_BUILD_FILE" -ReplacementItemList $RepoReplacementItemList_Build -Debug:$IS_DEBUG_ON
    } else {
        Write-Warning "对文件 '$GRADLE_BUILD_FILE' 的操作无法执行。（无有效仓库列表）"
    }
}


# 对项目中的测试文件执行替换
if ($IS_DEV_FEATURE_ENABLED) {
    if ($RepoReplacementItemList_Test) {
        $null=HandleFileBatch -InFile "$TEST_FILE" -ReplacementItemList $RepoReplacementItemList_Test -Debug:$IS_DEBUG_ON
    } else {
        Write-Warning "对文件 '$TEST_FILE' 的操作无法执行。（无有效仓库列表）"
    }
}
