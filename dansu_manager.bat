@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

rem 이 파일이 들어 있는 폴더의 한 단계 위에 Dansu 클라이언트를 설치합니다.
for %%I in ("%~dp0..") do set "INSTALL_ROOT=%%~fI"
set "CLIENT_DIR=%INSTALL_ROOT%\Dansu"
set "CLIENT_REPO=https://github.com/TeamDansu/Dansu.git"

rem Godot의 user://charts 실제 Windows 경로입니다.
set "CHARTS_PARENT=%APPDATA%\Godot\app_userdata\dansu"
set "CHARTS_DIR=%CHARTS_PARENT%\charts"
set "CHARTS_REPO=https://github.com/TeamDansu/Charts.git"

:menu
cls
echo ============================================================
echo                   Dansu 관리 도구
echo ============================================================
echo.
echo   클라이언트: "%CLIENT_DIR%"
echo   차트셋:     "%CHARTS_DIR%"
echo.
echo   [1] 클라이언트 설치
echo   [2] 클라이언트를 main 최신 버전으로 강제 업데이트
echo   [3] 차트셋 설치
echo   [4] 차트셋 push
echo   [5] 차트셋 pull
echo   [Q] 종료
echo.
choice /C 12345Q /N /M "실행할 작업을 선택하세요: "
if errorlevel 6 goto :quit
if errorlevel 5 goto :charts_pull
if errorlevel 4 goto :charts_push
if errorlevel 3 goto :charts_install
if errorlevel 2 goto :client_update
if errorlevel 1 goto :client_install
goto :menu

:client_install
cls
call :require_git
if errorlevel 1 goto :done

if exist "%CLIENT_DIR%\" goto :client_already_exists
echo [클라이언트 설치] %CLIENT_REPO%
echo 설치 위치: "%CLIENT_DIR%"
echo.
git clone --branch main --single-branch "%CLIENT_REPO%" "%CLIENT_DIR%"
if errorlevel 1 goto :operation_failed
echo.
echo 클라이언트 설치가 완료되었습니다.
goto :done

:client_already_exists
echo 이미 폴더가 존재하여 설치하지 않았습니다.
echo "%CLIENT_DIR%"
echo 기존 클라이언트를 갱신하려면 메뉴의 2번을 선택하세요.
goto :done

:client_update
cls
call :require_git
if errorlevel 1 goto :done
call :require_client_repo
if errorlevel 1 goto :done

echo [주의] 아래 클라이언트 폴더의 수정 사항을 모두 삭제하고
echo origin/main과 완전히 같은 상태로 되돌립니다.
echo.
echo "%CLIENT_DIR%"
echo.
choice /C YN /N /M "계속하시겠습니까? (Y/N): "
if errorlevel 2 goto :menu

echo.
echo origin 정보를 가져오는 중...
git -C "%CLIENT_DIR%" fetch origin
if errorlevel 1 goto :operation_failed

echo main 최신 버전을 적용하는 중...
git -C "%CLIENT_DIR%" reset --hard origin/main
if errorlevel 1 goto :operation_failed

echo.
echo 클라이언트 업데이트가 완료되었습니다.
goto :done

:charts_install
cls
call :require_git
if errorlevel 1 goto :done

if exist "%CHARTS_DIR%\.git\" goto :charts_already_installed
if not exist "%CHARTS_PARENT%\" mkdir "%CHARTS_PARENT%"
if errorlevel 1 goto :operation_failed

echo [차트셋 설치] %CHARTS_REPO%
echo 설치 위치: "%CHARTS_DIR%"
echo.
git clone --branch main --single-branch "%CHARTS_REPO%" "%CHARTS_DIR%"
if errorlevel 1 goto :charts_install_failed

echo.
echo 차트셋 설치가 완료되었습니다.
goto :done

:charts_already_installed
echo 차트셋이 이미 설치되어 있습니다.
echo "%CHARTS_DIR%"
echo 최신 파일을 받으려면 메뉴의 5번을 선택하세요.
goto :done

:charts_install_failed
echo.
echo 차트셋 설치에 실패했습니다.
echo 설치 위치에 기존 파일이 있다면 다른 곳에 백업한 뒤 다시 시도하세요.
goto :done

:charts_push
cls
call :require_git
if errorlevel 1 goto :done
call :require_charts_repo
if errorlevel 1 goto :done
call :require_charts_main
if errorlevel 1 goto :done

echo [차트셋 push] 현재 변경 내용
echo.
git -C "%CHARTS_DIR%" status --short
echo.
choice /C YN /N /M "위 변경 내용을 모두 저장하고 push하시겠습니까? (Y/N): "
if errorlevel 2 goto :menu

git -C "%CHARTS_DIR%" add -A
if errorlevel 1 goto :operation_failed

git -C "%CHARTS_DIR%" diff --cached --quiet
if errorlevel 1 goto :charts_commit
echo 새로 커밋할 변경 내용이 없습니다. 기존 커밋의 push를 시도합니다.
goto :charts_sync_and_push

:charts_commit
call :ensure_git_identity
if errorlevel 1 goto :done
set "COMMIT_MESSAGE="
set /p "COMMIT_MESSAGE=변경 내용 설명을 입력하세요 (Enter: Update charts): "
if not defined COMMIT_MESSAGE set "COMMIT_MESSAGE=Update charts"

git -C "%CHARTS_DIR%" commit -m "%COMMIT_MESSAGE%"
if errorlevel 1 goto :operation_failed

:charts_sync_and_push
echo.
echo 다른 팀원의 최신 변경 내용을 확인하는 중...
git -C "%CHARTS_DIR%" fetch origin
if errorlevel 1 goto :operation_failed
git -C "%CHARTS_DIR%" rebase origin/main
if errorlevel 1 goto :rebase_failed

echo GitHub에 업로드하는 중...
git -C "%CHARTS_DIR%" push origin HEAD:main
if errorlevel 1 goto :operation_failed

echo.
echo 차트셋 push가 완료되었습니다.
goto :done

:charts_pull
cls
call :require_git
if errorlevel 1 goto :done
call :require_charts_repo
if errorlevel 1 goto :done
call :require_charts_main
if errorlevel 1 goto :done

set "CHARTS_DIRTY="
for /f "delims=" %%I in ('git -C "%CHARTS_DIR%" status --porcelain') do set "CHARTS_DIRTY=1"
if defined CHARTS_DIRTY goto :charts_pull_dirty

echo [차트셋 pull] GitHub의 최신 변경 내용을 받는 중...
git -C "%CHARTS_DIR%" pull --rebase origin main
if errorlevel 1 goto :rebase_failed

echo.
echo 차트셋 pull이 완료되었습니다.
goto :done

:charts_pull_dirty
echo 저장하지 않은 차트 변경 내용이 있어 pull을 중단했습니다.
echo 먼저 메뉴의 4번으로 push하거나, 개발자에게 변경 내용 보존을 요청하세요.
echo.
git -C "%CHARTS_DIR%" status --short
goto :done

:require_git
where git >nul 2>&1
if not errorlevel 1 exit /b 0
echo Git이 설치되어 있지 않거나 PATH에서 찾을 수 없습니다.
echo Git for Windows를 설치한 뒤 이 파일을 다시 실행하세요.
exit /b 1

:require_client_repo
if not exist "%CLIENT_DIR%\.git\" goto :client_repo_missing
git -C "%CLIENT_DIR%" rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 goto :client_repo_missing
exit /b 0

:client_repo_missing
echo 클라이언트 Git 저장소를 찾을 수 없습니다.
echo 먼저 메뉴의 1번으로 설치하세요: "%CLIENT_DIR%"
exit /b 1

:require_charts_repo
if not exist "%CHARTS_DIR%\.git\" goto :charts_repo_missing
git -C "%CHARTS_DIR%" rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 goto :charts_repo_missing
exit /b 0

:charts_repo_missing
echo 차트셋 Git 저장소를 찾을 수 없습니다.
echo 먼저 메뉴의 3번으로 설치하세요: "%CHARTS_DIR%"
exit /b 1

:require_charts_main
set "CURRENT_BRANCH="
for /f "delims=" %%I in ('git -C "%CHARTS_DIR%" branch --show-current') do set "CURRENT_BRANCH=%%I"
if /I "%CURRENT_BRANCH%"=="main" exit /b 0
echo 차트셋의 현재 브랜치가 main이 아닙니다: %CURRENT_BRANCH%
echo 안전을 위해 작업을 중단했습니다. 개발자에게 문의하세요.
exit /b 1

:ensure_git_identity
set "GIT_USER_NAME="
set "GIT_USER_EMAIL="
for /f "delims=" %%I in ('git -C "%CHARTS_DIR%" config user.name') do set "GIT_USER_NAME=%%I"
for /f "delims=" %%I in ('git -C "%CHARTS_DIR%" config user.email') do set "GIT_USER_EMAIL=%%I"
if defined GIT_USER_NAME goto :ensure_git_email
set /p "GIT_USER_NAME=Git에 기록할 이름을 입력하세요: "
if not defined GIT_USER_NAME exit /b 1
git -C "%CHARTS_DIR%" config user.name "%GIT_USER_NAME%"
if errorlevel 1 exit /b 1

:ensure_git_email
if defined GIT_USER_EMAIL exit /b 0
set /p "GIT_USER_EMAIL=Git에 기록할 이메일을 입력하세요: "
if not defined GIT_USER_EMAIL exit /b 1
git -C "%CHARTS_DIR%" config user.email "%GIT_USER_EMAIL%"
if errorlevel 1 exit /b 1
exit /b 0

:rebase_failed
git -C "%CHARTS_DIR%" rebase --abort >nul 2>&1
echo.
echo 다른 팀원의 변경 내용과 충돌했거나 동기화에 실패했습니다.
echo 동기화 전 상태로 되돌렸습니다. 개발자에게 문의하세요.
goto :done

:operation_failed
echo.
echo 작업에 실패했습니다. 위의 Git 오류 메시지를 개발자에게 전달하세요.
goto :done

:done
echo.
pause
goto :menu

:quit
endlocal
exit /b 0
