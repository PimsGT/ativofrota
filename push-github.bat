@echo off
setlocal EnableExtensions

set "APP_DIR=%~dp0"
cd /d "%APP_DIR%"
set "GIT_PAGER=cat"

set "GIT_CONFIG_COUNT=1"
set "GIT_CONFIG_KEY_0=safe.directory"
set "GIT_CONFIG_VALUE_0=%APP_DIR%"

set "COMMIT_MESSAGE=Atualizar AtivoFrota"
if not "%~1"=="" set "COMMIT_MESSAGE=%~1"
set "FIREBASE_PROJECT=ativofrota-imobilizado"
set "FIREBASE_CLI=%APP_DIR%.work\tools\node_modules\.bin\firebase.cmd"

chcp 65001 >nul 2>&1

echo ================================================
echo AtivoFrota - GitHub e Firebase Hosting
echo ================================================
echo Pasta: %APP_DIR%
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

if exist "Acesso projeto Ativoimobilizado.txt" (
    echo AVISO: o arquivo de acesso foi mantido fora do envio.
    echo Ele sera ignorado pelo Git e nao sera publicado.
    >>nul echo Acesso projeto Ativoimobilizado.txt
)

git check-ignore -q "Acesso projeto Ativoimobilizado.txt" 2>nul
if errorlevel 1 (
    echo ERRO: o arquivo sensivel ainda nao esta protegido pelo .gitignore.
    echo Abra o arquivo .gitignore e inclua:
    echo Acesso projeto Ativoimobilizado.txt
    pause
    exit /b 1
)

echo Estado atual:
git --no-pager status --short
if errorlevel 1 (
    echo ERRO: nao foi possivel consultar o status do Git.
    pause
    exit /b 1
)

echo.
echo Adicionando os arquivos do projeto, respeitando o .gitignore...
git add --all
if errorlevel 1 (
    echo ERRO: falha ao adicionar os arquivos.
    pause
    exit /b 1
)

for /f "delims=" %%F in ('git diff --cached --name-only ^| findstr /I /R /C:"^\.env" /C:"\.env\." /C:"supabase/\.temp/" /C:"^\.firebase/" /C:"src/supabase-config\.js" /C:"src/firebase-config\.js" /C:"Acesso projeto Ativoimobilizado\.txt"') do (
    echo ERRO: arquivo sensivel ou temporario preparado: %%F
    git reset --quiet
    pause
    exit /b 1
)

echo.
echo Arquivos preparados para o commit:
git --no-pager diff --cached --name-status
if errorlevel 1 (
    echo ERRO: nao foi possivel verificar os arquivos preparados.
    pause
    exit /b 1
)

git diff --cached --quiet
if not errorlevel 1 (
    echo.
    echo Nao ha alteracoes novas para criar commit.
    echo O GitHub sera mantido como esta e o Hosting sera atualizado.
    set "CONFIRM="
    if /I "%~2"=="/S" (
        set "CONFIRM=S"
    ) else (
        set /p "CONFIRM=Publicar a versao atual no Firebase? Digite S ou N e pressione Enter: "
    )
    if /I not "%CONFIRM%"=="S" (
        echo Operacao cancelada. Nenhuma publicacao foi realizada.
        exit /b 0
    )
    goto confirm_deploy_only
)

echo.
echo Commit que sera criado:
echo %COMMIT_MESSAGE%
echo.
set "CONFIRM="
if /I "%~2"=="/S" (
    set "CONFIRM=S"
) else (
    set /p "CONFIRM=Criar commit, enviar ao GitHub e publicar no Firebase? Digite S ou N e pressione Enter: "
)
if /I not "%CONFIRM%"=="S" (
    echo Operacao cancelada. Nenhuma alteracao foi enviada.
    exit /b 0
)

git commit -m "%COMMIT_MESSAGE%"
if errorlevel 1 (
    echo ERRO: o commit nao foi criado.
    pause
    exit /b 1
)

git push -u origin main
if errorlevel 1 (
    echo.
    echo FALHA: o push nao foi concluido.
    echo Verifique a autenticacao do GitHub e a conexao.
    pause
    exit /b 1
)

echo.
echo Push concluido com sucesso.
echo Branch: main
git log -1 --oneline

:confirm_deploy_only
echo.
echo Verificando Firebase CLI...
if exist "%FIREBASE_CLI%" (
    set "FIREBASE_COMMAND=%FIREBASE_CLI%"
) else (
    where firebase.cmd >nul 2>&1
    if errorlevel 1 (
        echo ERRO: Firebase CLI nao foi encontrada.
        echo Instale o Firebase CLI ou execute a instalacao local do projeto.
        pause
        exit /b 1
    )
    set "FIREBASE_COMMAND=firebase.cmd"
)

echo Publicando no Firebase Hosting...
call "%FIREBASE_COMMAND%" deploy --only hosting --project "%FIREBASE_PROJECT%"
if errorlevel 1 (
    echo.
    echo FALHA: o deploy do Firebase nao foi concluido.
    echo O push do GitHub, se realizado, permanece concluido.
    pause
    exit /b 1
)

echo.
echo Publicacao concluida com sucesso no GitHub e no Firebase Hosting.
echo URL: https://ativofrota-imobilizado.web.app/
pause
exit /b 0
