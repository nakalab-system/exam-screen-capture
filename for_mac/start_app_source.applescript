-- 1_開始.app のソースコード (AppleScript)
-- このスクリプトは、同じディレクトリにある start.sh を呼び出します。

set scriptPath to POSIX path of ((path to me as text) & "Contents:Resources:start.sh")
do shell script "bash " & quoted form of scriptPath
