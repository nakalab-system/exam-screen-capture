-- 3_提出と停止.app のソースコード (AppleScript)

set scriptPath to POSIX path of (path to resource "submit.sh")
do shell script "bash " & quoted form of scriptPath
