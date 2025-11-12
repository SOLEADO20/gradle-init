@echo off
@setlocal enabledelayedexpansion

@REM Gradle项目镜像仓库初始化工具-启动器
@REM @Updated 2025-11-13 02:17
@REM @Created 2025-10-27 17:36
@REM @Author Kei
@REM @Version 1.0-stable

@REM 检查环境是否符合要求
if not exist ".\gradle" (echo:非Gradle项目环境！退出...) && exit /b 1

@REM 执行PS脚本
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process; & '%~dp0gradle-init.ps1';"

:end
echo:操作结束。如果一切就绪，请在IDE中重新打开项目，或者直接重启IDE，以确保更改生效。
exit /b
