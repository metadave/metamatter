require "rubygems"
require "wx"
require "mm/mm.rb"
require "mmgui/guiops.rb"

class MMWin < Wx::Frame
  
  def initialize    
    super(nil, -1, "Metamatter",Wx::DEFAULT_POSITION,Wx::Size.new(800,600))      
    puts "Double buffering = #{self.is_double_buffered}"
    @network = MM::Network.new
    @loadedops = MM::Op.getopnames.sort
    
    setup_menubar
    setup_opmenu
    setup_opinstmenu
    
    @draggingop = nil
    @dragoffx = 0
    @dragoffy = 0
    
    @selectlist = Array.new()

    @visops = Array.new()
    @visconns = Array.new()
    
    @shiftdown = false
    
    evt_paint { |event| on_paint(event) }
    evt_left_down { |event| on_left_down(event) }
    evt_left_up { |event| on_left_up(event) }
    evt_motion { |event| on_mouse_motion(event) }
    evt_right_up { |event| on_right_up(event) }
    evt_left_dclick { |event| on_left_dclick(event) }
    # for now. i know it's not totally correct, but it will do to test out multi selection
    evt_key_down() do |event|
      if event.shift_down then
        @shiftdown=true 
      end 
    end
    evt_key_up() {|event| @shiftdown=false }
    #evt_erase_background() { | event | event.skip() }

  end  
  
  def on_left_dclick(event)
    @clickedop = @visops.find { |op| op.rect.contains(event.get_x, event.get_y) }
    if not @clickedop.nil?
      opconfig = MMOpConfigFrame.new(@clickedop)
      opconfig.show()
    end
  end

  
  def on_mouse_motion(event)
    if not @draggingop.nil?
      # hmm.. not exactly sure why i need to add 2 to each of these. im assuming it's the width of
      # the border, but...why? shouldn't the border be included inside the rect?
      @oldrect = Wx::Rect.new(@draggingop.rect.x, @draggingop.rect.y, 
                              @draggingop.rect.width+2, @draggingop.rect.height+2)
      # and why do i need to subtract 1 from here?
      @draggingop.rect.x = event.get_x - @dragoffx -2 
      @draggingop.rect.y = event.get_y - @dragoffy -2

      # need to think this through... 
      # will accept flicker for now :-)      
      @visconns.each do |conn|
        if conn.dest_visop == @draggingop 
          #conn.repaint = true
        elsif conn.source_visop == @draggingop               
          #conn.repaint = true
        end
      end
      #peers.reject! {|item| item.nil?}     
      peers = Array.new
      peers << @draggingop.rect
      peers << @oldrect
      minx = peers.collect { |rect| rect.x }.min
      maxx = peers.collect { |rect| rect.x + rect.width }.max
      miny = peers.collect { |rect| rect.y }.min
      maxy = peers.collect { |rect| rect.y + rect.height }.max                                   
      fillrect = Wx::Rect.new(minx-3,miny-3,maxx+3,maxy+3)
      refresh_rect(fillrect)      
    end
  end
  
  def on_right_up(event)    
    if @selectlist.size == 2
      show_connect_menu(event)
    else
      @clickedop = @visops.find { |op| op.rect.contains(event.get_x, event.get_y) }
      if @clickedop.nil?
        @popup_location=event.get_position
        popup_menu(@opmenu)
      else
        popup_menu(@opinstmenu)
      end 
    end       
  end
  
  def on_left_down(event)
    @clickedop = @visops.find { |op| op.rect.contains(event.get_x, event.get_y) }
    if not @clickedop.nil?
      @draggingop = @clickedop 
      
      # pull the current op to the front
      @visops.delete(@draggingop)
      @visops <<  @draggingop

      @dragoffx = event.get_x - @draggingop.rect.x
      @dragoffy = event.get_y - @draggingop.rect.y
      if @selectlist.size >= 1 and @shiftdown
        @selectlist << @clickedop
      else
        @selectlist.clear
        @selectlist << @clickedop
      end
    else
      @selectlist.clear      
    end
    refresh
  end
  
  def on_left_up(event)
    @draggingop = nil
    @oldrect = nil
  end
  
  def on_paint(event)
    # a little bit of flicker moving around ops. need double buffering code,
    # but not sure how to do it in wx yet
    rect = self.get_client_size    
    # paint_buffered... 
    paint do |dc|
      gdc = Wx::GraphicsContext.create(dc)      

      ## cheap for now, lines appear to go to the edge of each op
      ## but they are really just painted behind. will dig out trig book.

      gdc.set_pen(Wx::WHITE_PEN)
      @visconns.each do |vc|
        sourcex = vc.source_visop.rect.x + vc.source_visop.rect.width/2
        sourcey = vc.source_visop.rect.y + vc.source_visop.rect.height/2
        destx = vc.dest_visop.rect.x + vc.dest_visop.rect.width/2
        desty = vc.dest_visop.rect.y + vc.dest_visop.rect.height/2                  
        gdc.stroke_line(sourcex, sourcey, destx, desty)
      end
      
      @visops.each do |visop|        

        r = visop.rect
        if @selectlist.member?(visop)
          gdc.set_brush(Wx::LIGHT_GREY_BRUSH)            
        else
          gdc.set_brush(Wx::MEDIUM_GREY_BRUSH)            
        end
        gdc.set_pen(Wx::BLACK_PEN)

        gdc.draw_rectangle(r.x,r.y,r.width,r.height)

        gdc.set_pen(Wx::WHITE_PEN)
        gdc.set_brush(Wx::BLACK_BRUSH)  

        font = gdc.create_font(Wx::Font.new(8, Wx::SWISS, Wx::NORMAL, Wx::NORMAL))
        gdc.set_font(font)                        
        gdc.draw_text(visop.op.getopid, r.x+3, r.y+3)                
        
      end            


    end
  end

  def setup_menubar
    menuBar = Wx::MenuBar.new()
    fileMenu = Wx::Menu.new()

    menuBar.append(fileMenu,"File")
    save = fileMenu.append(-1,"Save")
    load = fileMenu.append(-1,"Load")
    fileMenu.append(Wx::ID_EXIT,"Exit")
    
    networkMenu = Wx::Menu.new()
    start = networkMenu.append(-1,"Start")
    stop = networkMenu.append(-1,"Stop")

    menuBar.append(networkMenu,"Network")
    
    set_menu_bar(menuBar)
    
    evt_menu(Wx::ID_EXIT) { |event| exit }
    evt_menu(start.get_id) { |event| start_network }
    evt_menu(stop.get_id) { |event| stop_network } 

    evt_menu(save.get_id) { |event| save_network }
    evt_menu(load.get_id) { |event| load_network }
  end
  
  
  def setup_opinstmenu
    @opinstmenu = Wx::Menu.new("Op")
    delete = @opinstmenu.append(-1,"Delete")
    disconnect = @opinstmenu.append(-1,"Disconnect 1")
    evt_menu(delete) do |event| 
      puts "Deleting an op requires cleanup up orphaned connections!"
      @visops.delete(@clickedop) 
      refresh
    end
    evt_menu(disconnect) {|event| puts "Disconnect!" }
    
  end

  def setup_opmenu
    @opmenu = Wx::Menu.new("Opmenu")
    @loadedops.each_with_index do |op,index|     
      item = @opmenu.append(index,op[4..-1])
      evt_menu(index) {|event| op_menu_selection(event,index) }
    end
  end

  def op_menu_selection(event,index)
    puts "Creating #{@loadedops[index]} @ #{@popup_location}"    
    rect = Wx::Rect.new(@popup_location.x,@popup_location.y,100,40)    
    op = instance_eval "#{@loadedops[index]}.new()"    
    visop = VisOp.new(op,rect)
    @visops << visop
    @network.add(op)
    biggerrect = Wx::Rect.new(rect.x, rect.y, 
                                 rect.width+2, rect.height+2)
    refresh_rect(biggerrect,true)
  end

  def show_connect_menu(event)
    connectmenu = Wx::Menu.new("Connect")    
    source = @selectlist[0].op
    dest = @selectlist[1].op

    outputs = MM::Op.getOpOutputs(source.class)
    inputs = MM::Op.getOpInputs(dest.class)
    outputs.each do |output|
      inputs.each do |input|
        item = connectmenu.append(-1,"#{output} -> #{input}")
        evt_menu(item) do |event| 
          puts "Connecting #{output}->#{input}"           
          s = "source.#{output} >> dest.#{input}"          
          instance_eval s   
          @visconns << VisConn.new(@selectlist[0],@selectlist[1],output,input)
          refresh
        end
      end
    end
    popup_menu(connectmenu)
  end


  def start_network
    puts "Starting network"
    @network.run
  end
  
  def stop_network
    puts "Stopping network doesn't work :-("
    
  end


  def save_network
    File.open('c:\foo.m','w+') do |f|
      ops = @visops.collect  do |vop| 
        r = [vop.rect.x,vop.rect.y,vop.rect.width,vop.rect.height]
        [vop.op,r]
      end      
      Marshal.dump(ops,f)
      
    end
  end
  
  def load_network
    File.open('c:\foo.m') do |f|
      data = Marshal.load(f)
      data.each do |val|
        (op,r) = val
        @visops << VisOp.new(op,Wx::Rect.new(r[0],r[1],r[2],r[3]))
      end
    end
  end
  
end

class MMGui < Wx::App  
  def on_init  
    m = MMWin.new()
    m.show()  
  end
end

class MMOpConfigFrame < Wx::Frame
  attr_accessor :visop
  def initialize(visualop)
    super(nil, -1, visualop.op.getopid,Wx::DEFAULT_POSITION,Wx::Size.new(500,300),
          Wx::FRAME_TOOL_WINDOW | Wx::RESIZE_BORDER| Wx::SYSTEM_MENU|Wx::CAPTION|Wx::CLOSE_BOX|Wx::CLIP_CHILDREN)
    set_background_colour(Wx::LIGHT_GREY)
    @visop = visualop
    
    configs = @visop.op.allconfigs
    sizer= Wx::GridSizer.new(configs.keys.size,2,2,2)
    #sizer.add_growable_col(1)
    if configs.keys.size == 0 then
      label = Wx::StaticText.new(self,-1,"No parameters available")
      sizer.add(label,1,Wx::GROW|Wx::ALL,2)
    else       
      configs.keys.each do |k|
        value=@visop.op.send(k)     
        if not value.nil? then 
          label = Wx::StaticText.new(self,-1,k.to_s.capitalize)
          tc = Wx::TextCtrl.new(self,-1,value,Wx::DEFAULT_POSITION, Wx::DEFAULT_SIZE,Wx::TE_MULTILINE)
          sizer.add(label, 0, Wx::ALIGN_CENTER | Wx::GROW|Wx::ALL, 2)      
          sizer.add(tc, 1, Wx::GROW|Wx::ALL, 2)      
          evt_text(tc.get_id) { |event | @visop.op.send(k.to_s+"=",event.get_string) }
        end
      end
    end
    set_sizer(sizer)
    

  end
   
end


class VisOp 
  attr_accessor :op
  attr_accessor :rect
  
  def initialize(operator, rectangle)
    @op = operator
    @rect = rectangle
  end  
end

class VisConn
  attr_accessor :source_visop
  attr_accessor :source_output
  
  attr_accessor :dest_visop
  attr_accessor :dest_input

  #attr_accessor :repaint
  
  def initialize(source, dest, output, input)
    @source_visop = source
    @dest_visop = dest
    @source_output = output
    @dest_input = input
    #@repaint = true
  end
end

mmgui = MMGui.new
mmgui.main_loop
