set scriptPath to POSIX path of ((path to me as text) & "Contents:Resources:submit_app_source.applescript")
-- 注意: 実際の.app内では Contents/Resources/submit.sh を呼び出すように構成します
set scriptPath to POSIX path of ((path to me as text) & "Contents:Resources:submit.sh")
do shell script "bash " & quoted form of scriptPath
