#課題レポート(パッチパネルの機能拡張)
更新日：(2016.10.20)

##課題
```
課題内容：
パッチパネルに機能を追加する．
授業で説明のあったパッチの追加と削除以外に，以下の機能を追加する．
１．ポートのミラーリング
２．パッチとポートミラーリングの一覧
```

##目次  
1. [ポートのミラーリング](#mirror)  
2. [パッチとポートミラーリングの一覧](#print)  
3. [ミラーリングの削除](#del_mirror)
4. [バグ報告](#bug)  

<a id="mirror"></a>
##1.ポートのミラーリング  
下記のようにメソッドを追加した．  
* [./lib/patch_panel.rb](https://github.com/handai-trema/patch-panel-r-narimoto/blob/master/lib/patch_panel.rb)  
###create_mirror_patchメソッド  
add_flow_mirror_entriesメソッドが正しく実行された（flow_modメッセージ送信された）時にのみ，ミラーリングリストであるハッシュ@m_patchにポートのペアを格納する．
パッチの追加では，ポートのペアをソーティングしていたが，ここではどちらがミラーポートかを判断するためにソートは行っていない．  
```ruby
@m_patch[dpid] << [port, mirror] if add_flow_mirror_entries dpid, port, mirror
```  
###add_flow_mirror_entriesメソッド  
まず既存のミラーリングを@m_patchから探す．すでにミラーポートが設定されているモニターポートである場合にはfalseを返して終了する．こうすることで，ミラーリングの重複が起こらないようにしている．同様の方法を用い，パッチの追加に関しても設定の重複がおこらないように実装を追加した．  
```ruby
@m_patch[dpid].each do |ports|
  return false if ports[0] == port
end
```  
そうでない場合は，モニターポートのパッチを@patchより探し，モニターポート宛のパケットの送信元ポートを特定する．この際，モニターポートに対するパッチが存在しない場合は，ミラーリングを作成できない為，falseを返して終了する．  
```ruby
port_src = nil
@patch[dpid].each do |port_a, port_b|
  port_src = port_a if port_b == port
  port_src = port_b if port_a == port
end
return false if port_src == nil
```  
見つかったポートと，モニターポートそれぞれが送信元であるflow_modを一旦削除する．  
```ruby
send_flow_mod_delete(dpid, match: Match.new(in_port: port_src))
send_flow_mod_delete(dpid, match: Match.new(in_port: port))
```  
その後，それぞれに対して送信先としてミラーポートを追加したflow_modメッセージを送信し，終了する．  
```ruby
send_flow_mod_add(dpid,
                  match: Match.new(in_port: port_src),
                  actions: {
                      SendOutPort.new(port),
                      SendOutPort.new(mirror),
                  })
send_flow_mod_add(dpid,
                  match: Match.new(in_port: port),
                  actions: {
                      SendOutPort.new(port_src),
                      SendOutPort.new(mirror),
                  })
return true
```
* [./bin/patch_panel](https://github.com/handai-trema/patch-panel-r-narimoto/blob/master/bin/patch_panel)  
```ruby
desc 'Create a mirror'
arg_name 'dpid port mirror'
command :m_create do |c|
  c.desc 'Location to find socket files'
  c.flag [:S, :socket_dir], default_value: Trema::DEFAULT_SOCKET_DIR

  c.action do |_global_options, options, args|
    dpid = args[0].hex
    port = args[1].to_i
    mirror = args[2].to_i
    Trema.trema_process('PatchPanel', options[:socket_dir]).controller.
      create_mirror_patch(dpid, port, mirror)
  end
end
```  
既にあった実装を参考に，次のコマンドにてportをモニターポート，mirrorをミラーポートとするミラーリングを作成できるようサブコマンドを実装した．  
```
./bin/patch_panel m_create [dpid] [port] [mirror]
```  
###動作確認  
次の手順にてミラーリングが正しく生成できていることを確認した．  
```
スイッチdpid:0xabc,ポート[1-3]:host[1-3](192.168.0.[1-3])
1.host1とhost2間のパッチを作成
2.host1をhost3でミラーリングするパッチを作成
3.host1からhost2へパケット送信
4.host2からhost1へパケット送信
```
実行結果は以下のようになった．  
```
$ ./bin/patch_panel create 0xabc 1 2
$ ./bin/patch_panel m_create 0xabc 1 3
$ ./bin/trema send_packets --source host1 --dest host2
$ ./bin/trema show_stats host1
Packets sent:
  192.168.0.1 -> 192.168.0.2 = 1 packet
$ ./bin/trema show_stats host2
Packets received:
  192.168.0.1 -> 192.168.0.2 = 1 packet
$ ./bin/trema show_stats host3
$ ./bin/trema send_packets --source host2 --dest host1
$ ./bin/trema show_stats host1
Packets sent:
  192.168.0.1 -> 192.168.0.2 = 1 packet
Packets received:
  192.168.0.2 -> 192.168.0.1 = 1 packet
$ ./bin/trema show_stats host2
Packets sent:
  192.168.0.2 -> 192.168.0.1 = 1 packet
Packets received:
  192.168.0.1 -> 192.168.0.2 = 1 packet
$ ./bin/trema show_stats host3
$ ./bin/trema dump_flows patch_panel
NXST_FLOW reply (xid=0x4):
 cookie=0x0, duration=93.839s, table=0, n_packets=1, n_bytes=42, idle_age=70, priority=0,in_port=1 actions=output:2,output:3
 cookie=0x0, duration=93.843s, table=0, n_packets=1, n_bytes=42, idle_age=13, priority=0,in_port=2 actions=output:1,output:3
```  
結果より，host3へパケットが到達していないことがわかる．しかしながら，パッチパネルのdump_flowsを確認すると，実装通りポート1とポート2からのパケットがそれぞれポート3のミラーポートへ送信する設定となっていることが確認できた．  
これは，パケットの送信先アドレス(mac,ip)が変更されておらず，host3宛のパケットではないため，届いてはいるが受け取られていないものと考えられる．対策として，actionsの中においてパケットの宛先を変更するか，host3は自分宛てでないパケットも受信する設定にするかの２つが考えられるが，今回は実装を見送った．  

<a id="print"></a>
##2.パッチとポートミラーリングの一覧  
下記のようにメソッドを追加した．  
* [./lib/patch_panel.rb](https://github.com/handai-trema/patch-panel-r-narimoto/blob/master/lib/patch_panel.rb)  
###print_patch_mirrorメソッド  
```ruby
def print_patch_mirror(dpid)
  ret = Array.new()
  ret << @patch
  ret << @m_patch
  return ret
end
```  
指定したdpidのパッチ（@patch）とミラーリング（@m_patch）のリストが格納されているハッシュを一つの配列に格納して返すだけ．  
* [./bin/patch_panel](https://github.com/handai-trema/patch-panel-r-narimoto/blob/master/bin/patch_panel)  
```ruby
desc 'Print patches and mirrors'
arg_name 'dpid ret patch m_patch'
command :print do |c|
  c.desc 'Location to find socket files'
  c.flag [:S, :socket_dir], default_value: Trema::DEFAULT_SOCKET_DIR

  c.action do |_global_options, options, args|
    dpid = args[0].hex
    ret = Trema.trema_process('PatchPanel', options[:socket_dir]).controller.
      print_patch_mirror(dpid)
    @patch = ret[0]
    @m_patch = ret[1]
    p "Patch list: (port <=> port)"
    @patch[dpid].each do |port_a, port_b|
      print(port_a, " <=> ", port_b, "\n")
    end
    p "Mirror list: (port => mirror)"
    @m_patch[dpid].each do |port, mirror|
      print(port, " => ", mirror, "\n")
    end
  end
end
```  
次のコマンドでリストが見られるように実装した．  
```
./bin/patch_panel print [dpid]
```  
print_patch_mirrorメソッドの戻り値を配列に格納し，要素0を@patchに，要素1を@m_patchに格納してそれぞれ１つずつ走査し，表示する．  
###動作確認  
次の手順で動作確認を行った．  
また，1.においてパッチの存在しないミラーリングが生成できないこと，既にあるミラーリングに対しては重複するように生成できないことも確認した．  
```
1.host1をhost3でミラーリングするパッチの作成（失敗）
2.host1とhost2間のパッチを作成
3.host1をhost3でミラーリングするパッチの作成
4.もう一度3を試みる（失敗）
```  
実行結果は以下の通りとなった．  
```
$ ./bin/patch_panel m_create 0xabc 1 3
$ ./bin/patch_panel print 0xabc
"Patch list: (port <=> port)"
"Mirror list: (port => mirror)"
$ ./bin/patch_panel create 0xabc 1 2
$ ./bin/patch_panel print 0xabc
"Patch list: (port <=> port)"
1 <=> 2
"Mirror list: (port => mirror)"
$ ./bin/patch_panel m_create 0xabc 1 3
$ ./bin/patch_panel print 0xabc
"Patch list: (port <=> port)"
1 <=> 2
"Mirror list: (port => mirror)"
1 => 3
$ ./bin/patch_panel m_create 0xabc 1 3
$ ./bin/patch_panel print 0xabc
"Patch list: (port <=> port)"
1 <=> 2
"Mirror list: (port => mirror)"
1 => 3
```  
結果より，ミラーリングの生成の動作が正しく行えていること及びパッチとミラーリングのリスト表示が正しく実装できていることが確認できた．  

<a id="del_mirror"></a>
##3.ミラーリングの削除  
追加として，作成したミラーリングを削除するメソッドも実装した．  
* [./lib/patch_panel.rb](https://github.com/handai-trema/patch-panel-r-narimoto/blob/master/lib/patch_panel.rb)  
###delete_mirror_patchメソッド  
ミラーリングの作成時と同様に， delete_flow_mirror_entriesメソッドが正しく実行され，戻り値としてtrueが返された時のみ，ミラーリングのハッシュを削除するように実装している．  
```ruby
@m_patch[dpid].delete([port, mirror]) if delete_flow_mirror_entries dpid, port, mirror
```  
###delete_flow_mirror_entriesメソッド  
まず，削除したいエントリが存在するのかを@m_patchを走査して探す．なかった場合には，falseを返して終了する．同様の方法でパッチの削除にも実装した．  
```ruby
is_no_entry = true
@m_patch[dpid].each do |ports|
  is_no_entry = false if ports == [port, mirror]
end
return false if is_no_entry
```  
次にエントリを削除するため，モニターポートとパッチが作成されているもう１つのポートを@patchから探す．そして，モニターポートと探したポートが送信元となるflow_modエントリを一度削除する．これらは，ミラーリングの作成の時と同じ処理である．  
最後に，２つのポート間のflow_modメッセージを送信する．これで，ミラーリングを作成する前の状態に戻る．  
```ruby
send_flow_mod_add(dpid,
                  match: Match.new(in_port: port_src),
                  action: SendOutPort.new(port))
send_flow_mod_add(dpid,
                  match: Match.new(in_port: port),
                  actions: SendOutPort.new(port_src))
return true
```  
###動作確認  
以下の手順で動作確認を行った．  
```
1.host1とhost2間でパッチを作成
2.host1をhost3間でミラーリングするパッチを作成
3.host1のミラーリングを削除
4.host1とhost2間でパケットを送受信
```  
実行結果は以下の通りとなった．  
```
$ ./bin/patch_panel create 0xabc 1 2
$ ./bin/patch_panel m_create 0xabc 1 3
$ ./bin/patch_panel print 0xabc
"Patch list: (port <=> port)"
1 <=> 2
"Mirror list: (port => mirror)"
1 => 3
$ ./bin/patch_panel m_delete 0xabc 1 3
$ ./bin/patch_panel print 0xabc
"Patch list: (port <=> port)"
1 <=> 2
"Mirror list: (port => mirror)"
$ ./bin/trema send_packets --source host1 --dest host2
$ ./bin/trema send_packets --source host2 --dest host1
$ ./bin/trema show_stats host1
Packets sent:
  192.168.0.1 -> 192.168.0.2 = 1 packet
Packets received:
  192.168.0.2 -> 192.168.0.1 = 1 packet
$ ./bin/trema show_stats host2
Packets sent:
  192.168.0.2 -> 192.168.0.1 = 1 packet
Packets received:
  192.168.0.1 -> 192.168.0.2 = 1 packet
$ ./bin/trema dump_flows patch_panel
NXST_FLOW reply (xid=0x4):
 cookie=0x0, duration=16.008s, table=0, n_packets=1, n_bytes=42, idle_age=10, priority=0,in_port=1 actions=output:2
 cookie=0x0, duration=16.011s, table=0, n_packets=1, n_bytes=42, idle_age=8, priority=0,in_port=2 actions=output:1
```  
結果より，正しくエントリの追加削除が行えており，ミラーリング作成前に状態が戻っていることが確認できた．  

<a id="bug"></a>
##4.バグ報告  
配布されたプログラム（lib/patch_panel.rb）にバグと思わしき箇所を発見したのでここで報告する．  
箇所は，ハッシュ（@patch）に対する追加の部分である．実装は下記のようになっていた．
```ruby
@patch[dpid] += [port_a, port_b].sort
```  
一見追加できているように見えるが，実際の@patchの中身を出力してみると，次のようになっていた．  
```
[1, 2]
```  
本来は，下記のようになっているべきであると考える．  
```
[[1, 2]]
```  
上記状態より更にエントリを追加すると次のようになる．  
```
[1, 2, 3, 4]
＃本来は[[1, 2], [3, 4]]となるべきだと考える
```  
ポート番号の重複するエントリを追加しなければこのままの実装でも問題無いかもしれないが，
スライド等での説明は二次元配列であった．  
よって，下記のように実装を変更して今回は用いた．
```ruby
@patch[dpid] << [port_a, port_b].sort
```  
