self_id = Process.getpgrp
drb_process = `ps -ef | grep gitlab-git-server`
drb_process.split("\n").each do |pro|
  p pro
  pro_array = pro.split(" ")
  if pro_array[1] != self_id.to_s && pro_array[7]=='ruby' && pro_array[2] != self_id.to_s
    p "kill #{pro_array[1]}"
    Process.kill('INT', pro_array[1].to_i)
  end
end
