#encoding: UTF-8
load File.expand_path('window_login.rb', File.dirname(__FILE__))
class NBX < Game
  Version = "20090622"
  Port=2583
  RS = "￠"
  def initialize
    super
    require 'digest/md5'
    load File.expand_path('action.rb', File.dirname(__FILE__))
    load File.expand_path('event.rb', File.dirname(__FILE__))
    load File.expand_path('user.rb', File.dirname(__FILE__))
  end


  def login(username)
    connect
    Game_Event.push Game_Event::Login.new(User.new('localhost', username)) if @conn_hall
  end

  def host(name=@user.name)
    @room = Room.new(@user.id, name, @user)
    Game_Event.push Game_Event::Host.new(@room)
    send(nil, "NewRoom", @room.player1.name)
    @conn_room_server = TCPServer.new '0.0.0.0', Port  #为了照顾NBX强制IPv4
    @accept_room = Thread.new{Thread.start(@conn_room_server.accept) {|client| accept(client)} while @conn_room_server}
  end
  def action(action)
    if @room.player2
      action.from_player = false
      send(:room, action.escape)
      action.from_player = true
    end
  end

  def refresh
    send(nil, 'NewUser', @user.name, 1)
  end
  def join(host, port=Port)
    Thread.new do
      begin
        connect_loop TCPSocket.new(host, port)
      rescue
        Game_Event.push Game_Event::Error.new("网络错误", "连接服务器失败")
        $log.error [exception.inspect, *exception.backtrace].join("\n")
      end
    end
  end

  def exit
    send(:room, "关闭游戏王NetBattleX  2.7.2▊▊▊730462") rescue nil
    @recv_hall.kill rescue nil
    @conn_hall.close rescue nil
    @conn_hall = nil
    @conn_room.close rescue nil
    @conn_room = nil
    @conn_room_server.close rescue nil
    @conn_room_server = nil
  end
  def exit_room
    
  end
  private
  def send(user, head, *args)
    case user
    when User  #大厅里给特定用户的回复
      @conn_hall.send("#{head}|#{args.join(',')}", 0, user.host, Port) if @conn_hall
    when nil #大厅里的广播
      @conn_hall.send("#{head}|#{args.join(',')}", 0, '<broadcast>', Port) if @conn_hall
    when :room #房间里，发给对手和观战者
      @conn_room.write(head.gsub("\n", "\r\n") + RS) if @conn_room
    when :watchers #房间里，发给观战者
      
    end
    
  end
  def connect
    require 'socket'
    require 'open-uri'
    begin
      @conn_hall = UDPSocket.new
      @conn_hall.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
      @conn_hall.bind('0.0.0.0', Port) 
      Thread.abort_on_exception = true
      @recv_hall = Thread.new do
        begin
          recv *@conn_hall.recvfrom(1024) while @conn_hall
        rescue Exception => exception
          self.exit
          Game_Event.push Game_Event::Error.new(exception.class.to_s, exception.message)
          $log.error('nbx-connect-1') {[exception.inspect, *exception.backtrace].join("\n")}
        end
      end
    rescue Exception => exception
      self.exit
      Game_Event.push Game_Event::Error.new(exception.class.to_s, exception.message)
      $log.error('nbx-connect-2') {[exception.inspect, *exception.backtrace].join("\n")}
    end
  end
  def accept(client)
    if @conn_room #如果已经连接了，进入观战
      
    else #连接
      connect_loop(client)
    end
  end
  def recv_room(info)
    info.chomp!(RS)
    info.gsub!("\r\n", "\n")
    $log.info  ">> #{info}"
    Game_Event.push Game_Event.parse info
  end
  def connect_loop(conn)
    @conn_room = conn
    begin
      @conn_room.set_encoding "GBK", "UTF-8", :invalid => :replace, :undef => :replace
      @room = Room.new(@user.id, @user.name, @user)
      Game_Event.push Game_Event::Join.new(@room)
      send(:room, "[VerInf]|#{Version}")
      send(:room, "▓SetName:#{@user.name}▓")
      send(:room, "[☆]开启 游戏王NetBattleX Version  2.7.0\r\n[10年3月1日禁卡表]\r\n▊▊▊E8CB04")
      @room.player2 = User.new(conn.addr[2], "对手")
      while info = @conn_room.gets(RS)
        recv_room(info)
      end
    rescue Exception => exception
      Game_Event.push Game_Event::Error.new(exception.class.to_s, exception.message)
      $log.error('nbx-connect-loop') { [exception.inspect, *exception.backtrace].join("\n")}
    ensure
      @conn_room.close
      @conn_room = nil
    end
  end
  def recv(info, addrinfo)
    $log.info  ">> #{info} -- #{addrinfo[2]}"
    Socket.ip_address_list.each do |localhost_addrinfo|
      if localhost_addrinfo.ip_address == addrinfo[3]
        addrinfo[2] = 'localhost'
        break
      end
    end
    Game_Event.push Game_Event.parse(info, addrinfo[2])
  end
end

