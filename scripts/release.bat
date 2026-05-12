@echo off
setlocal

set "FILE_NAME=rfc-windows-x86_64.exe"
set "BIN_FOLDER=bin"
mkdir %BIN_FOLDER% 2>nul

echo Building %FILE_NAME% on Windows/x86_64...
v -prod . -o "%BIN_FOLDER%\%FILE_NAME%"
if errorlevel 1 exit /b %errorlevel%

CertUtil -hashfile "%BIN_FOLDER%\%FILE_NAME%" SHA256 > "%BIN_FOLDER%\%FILE_NAME%.sha256"
CertUtil -hashfile "%BIN_FOLDER%\%FILE_NAME%" SHA512 > "%BIN_FOLDER%\%FILE_NAME%.sha512"
