# this is a lot more simple in rails 3, and in fact, must be
# changed to a more simple usage because .rollback_active_record_state!
# no longer works.

module Azimux
  module MultimodelTransactions
    module ActionController
      protected

      # group together transactions based on connection.
      # if only one database is involved, there will only be
      # once connection, regardless of how many objects are used.
      def ax_multimodel_transaction objects, options = {}, &block
        raise "obsolete"
        reraise = options[:reraise]
        to_enter = []

        to_connections = proc do |array|
          array.map do |object|
            if object.is_a? ActiveRecord::Base
              object.connection
            elsif object.is_a?(Class) && object.ancestors.include?(ActiveRecord::Base)
              object.connection
            elsif object.is_as?(ActiveRecord::ConnectionAdapters::AbstractAdapter)
              object
            else
              raise "Not sure how to convert #{object} into a connection"
            end
          end
        end

        #begin
        already_in = options[:already_in] || []
        already_in = [already_in] unless already_in.is_a? Array
        already_in = to_connections.call(already_in)

        objects = to_connections.call(objects)

        to_enter = objects.uniq - already_in.uniq

        to_enter.reverse.inject(block) do |proc_object, conn|
          proc do
            conn.transaction do
              proc_object.call
            end
          end
        end.call

        #        rescue Azimux::MultimodelTransactions::Rollback
        #          raise if reraise
        #          raise ActiveRecord::Rollback if !to_enter.empty?
        #        end
      end

      # this can help with saving multiple models in a controller, especially
      # if the number of models is unknown.  If the exact models are known (which is usually the case),
      # it is probably best to just write the code directly.
      def ax_multimodel_transactional_if(objects, options = {})
        if_proc = options[:if]
        is_true = options[:is_true]
        is_false = options[:is_false]
        retval = nil

        if objects.blank?
          raise "ax_multimodel_transactional_if must be called with an array of the objects involved"
        end

        objects.each do |object|
          if !object.class.ancestors.include?(ActiveRecord::Base)
            raise "ax_multimodel_transactional_if must be called with an array of the ActiveRecord::Base objects.
                      #{object} is not an instance of ActiveRecord::Base"
          end
        end

        unless if_proc
          raise "You must pass in a proc object using :if =>"
        end

        bool_proc = proc do
          if if_proc.call
            retval = is_true.call if is_true
          else
            raise Azimux::MultimodelTransactions::Rollback
          end
        end

        begin
          #we need to call multimodel_transaction, even if we're already in it.
          #ax_multimodel_transaction models do
          objects.reverse.inject(bool_proc) do |proc_object, object|
            proc do
              object.transaction do
                proc_object.call
              end
            end
          end.call
          #end
        rescue Azimux::MultimodelTransactions::Rollback
          retval = if is_false
            is_false.call
          else
            false
          end
        end

        retval
      end

    end

  end
end

class Azimux::MultimodelTransactions::Rollback < Exception
end