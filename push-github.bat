@echo off
setlocal

set "APP_DIR=%~dp0"
cd /d "%APP_DIR%"

echo ================================================
echo AtivoFrota - Push para o GitHub
echo ================================================
echo.

git --version >nul 2>&1
if errorlevel 1 (
    echo ERRO: Git nao foi encontrado no PATH.
    echo Instale o Git for Windows e tente novamente.
    pause
    exit /b 1
)

if not exist ".git" (
    echo ERRO: esta pasta nao e um repositorio Git:
    echo %APP_DIR%
    pause
    exit /b 1
)

rem O workspace pode ter sido criado por outra conta do Windows.
rem A excecao abaixo vale somente para esta execucao do script.
set "GIT_CONFIG_COUNT=1"
set "GIT_CONFIG_KEY_0=safe.directory"
set "GIT_CONFIG_VALUE_0=%APP_DIR%"

echo Remoto configurado:
git remote -v
echo.

echo Branch atual:
git branch --show-current
echo.

git status --short
if errorlevel 1 (
    echo ERRO: nao foi possivel consultar o status do Git.
    pause
    exit /b 1
)

echo.
echo O comando a ser executado sera:
echo git push -u origin main
echo.
choice /C SN /N /M "Continuar com o push? [S/N] "
if errorlevel 2 (
    echo Operacao cancelada.
    exit /b 0
)

git push -u origin main
if errorlevel 1 (
    echo.
    echo FALHA: o push nao foi concluido.
    echo Verifique o acesso a https://github.com e a autenticacao do Git.
    echo Nenhuma senha ou token e armazenado neste arquivo.
    pause
    exit /b 1
)

echo.
echo Push concluido com sucesso.
pause
exit /b 0
