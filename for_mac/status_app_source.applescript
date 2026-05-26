-- 2_状況確認.app のソースコード (AppleScript)

set scriptPath to POSIX path of (path to resource "status.sh")
do shell script "bash " & quoted form of scriptPath
