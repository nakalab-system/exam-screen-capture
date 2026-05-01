set scriptPath to POSIX path of ((path to me as text) & "Contents:Resources:status.sh")
do shell script "bash " & quoted form of scriptPath
