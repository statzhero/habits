# Author: Michael Forrest | Good To Hear | http://goodtohear.co.uk | License terms: credit me.
class HabitListViewController < ATSDragToReorderTableViewController
  SECTIONS = [:active,:carried_over,  :not_today, :inactive]
  attr_accessor :nav
  def init
    if super
      build
    end
    self
  end

  def loadGroups
    @groups = [
      Habit.active_today.sort, Habit.carried_over.sort, 
      Habit.active_but_not_today.sort, Habit.inactive.sort]
  end
  
  def build
    self.restorationIdentifier = "List"
    @reload_queue = Dispatch::Queue.concurrent(:default)
    
    tableView.separatorInset = [0,40,0,0] # [0,0,0,0]
    tableView.showsVerticalScrollIndicator = false

    loadGroups
    
    @now = Time.now
    
    self.view.dataSource = self
    self.view.reloadData
    
    @loading = UIView.alloc.initWithFrame [[0,0], [320,3000]]
    @loading.backgroundColor = UIColor.blackColor
    @loading.alpha = 0
    @loading.userInteractionEnabled = false
    self.view.addSubview @loading

    @easter_egg = ScrollEasterEggView.alloc.initWithFrame [[0,-200],[320,200]]
    self.view.addSubview @easter_egg

  end
  def scrollViewDidScroll scrollView
    return if !@easter_egg 
    offset = -scrollView.contentOffset.y
    return if offset < 0 
    @easter_egg.scrolledTo offset
  end
  def refresh
    @loading.alpha = 0.2
    @reload_queue.async do    
      @now = Time.now
      @day_navigation.date = @now unless @day_navigation.nil?
      @not_required_today_title = nil
      loadGroups
      Dispatch::Queue.main.async do
        self.view.reloadData
        @loading.alpha = 0
      end
    end
    
  end
  def viewWillDisappear animated
    # self.navigationItem.title = "ALL"
  end

  #swiper table dataSource
  def tableView tableView, numberOfRowsInSection: section_index
    return 0 if  @groups.nil? or @groups[section_index].nil?
    @groups[section_index].count
  end
  
  def numberOfSectionsInTableView tableView
    SECTIONS.count
  end

  def habitAtIndexPath(indexPath)
    @groups[section][indexPath.row]
  end

  CELLID = 'HabitRow'
  
  def configureCell cell, forIndexPath: indexPath
    cell.now = @now
    habit = @groups[indexPath.section][indexPath.row]
    cell.inactive = false
    cell.habit = habit
    unless habit.nil? 
      habit_is_required_today = habit.active && habit.days_required[Time.new.wday]
      if habit_is_required_today
        cell.set_color habit.color
      else 
        cell.set_color Colors::COBALT
        cell.inactive = true
        cell.habit = habit
      end
      if indexPath.section == SECTIONS.index(:carried_over)
        cell.inactive = false
        cell.set_color habit.color
        cell.habit = habit
      end
    end
    cell
  end
  
  def tableView tableView, cellForRowAtIndexPath: indexPath
    cell = tableView.dequeueReusableCellWithIdentifier(CELLID) || HabitCell.alloc.initWithStyle(UITableViewCellStyleDefault, reuseIdentifier:CELLID)
    configureCell cell, forIndexPath: indexPath
  end
  def cellIdenticalToCellAtIndexPath indexPath, forDragTableViewController: dragTableViewController
    cell = HabitCell.alloc.initWithStyle(UITableViewCellStyleDefault, reuseIdentifier:nil)
    cell.layer.shadowColor = UIColor.blackColor.CGColor
    cell.layer.shadowOpacity = 0.5
    cell.layer.shadowRadius = 5
    cell.layer.shadowOffset = [0,1]
    configureCell cell, forIndexPath: indexPath
  end
  def tableView tableView, heightForHeaderInSection: section
    if SECTIONS.index(:active) == section
      return 44
    end
    return @groups[section].count > 0 ? 20 : 0
  end
  
  def tableView tableView, viewForHeaderInSection: section
    if section == SECTIONS.index(:carried_over)
      unless @carried_over
        @carried_over = InactiveHabitsHeader.alloc.initWithTitle("Carried over from yesterday")
      end
      return @carried_over
    end
    if section == SECTIONS.index(:active)
      @day_navigation ||= DayNavigation.alloc.init
      @day_navigation.date = @now
      return @day_navigation
    end
    if section == SECTIONS.index(:not_today)
      return @not_required_today_title ||= InactiveHabitsHeader.alloc.initWithTitle( "Not on #{Calendar::DAY_NAMES_PLURAL[ Time.new.wday ]}")
    end
    if section == SECTIONS.index(:inactive)
      return @inactive_title ||= InactiveHabitsHeader.alloc.init
    end
  end

  def tableView tableView, moveRowAtIndexPath: indexPath, toIndexPath: newIndexPath 
    moved = @groups[indexPath.section][indexPath.row]
    if moved.nil?
      #TFLog "couldn't find an appropriate habit in hte tableView moveRow callback so returning"
      return
    end
    section_id = SECTIONS[newIndexPath.section] 
    moved.active = section_id != :inactive
    unless section_id == :inactive
      moved.days_required[Time.new.wday] = section_id == :active
    end

    @groups[indexPath.section].delete_at indexPath.row
    @groups[newIndexPath.section].insert newIndexPath.row, moved

    return if section_id == :active_but_not_today  # because we don't want to mess up the order in this case.
    for group in @groups
      group.each_with_index do |habit, index|
        habit.order = index
      end
    end
    Habit.save!
  end
  # swiper table delgate
  def tableView tableView, didSelectRowAtIndexPath:indexPath
    habit = @groups[indexPath.section][indexPath.row]
    detail = HabitDetailViewController.alloc.initWithHabit habit
    self.nav.pushViewController detail, animated: true
  end

  def addItem
    new_habit = Habit.new
    Habit.all.push new_habit
    loadGroups
    section = SECTIONS.index(new_habit.active ? :active : :inactive)
    view.beginUpdates
    indexPath = NSIndexPath.indexPathForRow(@groups[section].count - 1, inSection: section)
    tableView.insertRowsAtIndexPaths [indexPath], withRowAnimation: UITableViewRowAnimationAutomatic
    view.endUpdates
    tableView tableView, didSelectRowAtIndexPath: indexPath
  end

end
