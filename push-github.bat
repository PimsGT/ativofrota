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

chcp 65001 >nul 2>&1

echo ================================================
echo AtivoFrota - Commit e Push para o GitHub
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
    echo O repositorio ja esta atualizado ou os arquivos nao foram alterados.
    pause
    exit /b 0
)

echo.
echo Commit que sera criado:
echo %COMMIT_MESSAGE%
echo.
set "CONFIRM="
if /I "%~2"=="/S" (
    set "CONFIRM=S"
) else (
    set /p "CONFIRM=Criar commit e enviar para o GitHub? Digite S ou N e pressione Enter: "
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
pause
exit /b 0
