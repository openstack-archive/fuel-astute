module Deployment
  # This exception is raised if you have passed an incorrect object to a method
  class InvalidArgument < StandardError
    attr_reader :argument
    def initialize(object, message='Argument is invalid!', argument=nil)
      @argument = argument
      message = "#{object}: #{message}"
      message += " (#{argument})" if argument
      super(message)
    end
  end

  # There is no task with such name is the graph
  class NoSuchTask < StandardError
    attr_reader :task
    def initialize(object, message='There is no such task!', task=nil)
      @task = task
      message = "#{object}: #{message}"
      message += " Name: #{task}" if task
      super(message)
    end
  end

  # You have directly called an abstract method that should be implemented in a subclass
  class NotImplemented < StandardError
  end

  # Loop detected in the graph
  class LoopDetected < StandardError
    attr_reader :tasks
    def initialize(object, message='Loop detected!', tasks=[])
      @tasks = tasks
      message = "#{object}: #{message}"
      if tasks.any?
        message += " Path: #{tasks.join ', '}"
      end
      super(message)
    end
  end
end
