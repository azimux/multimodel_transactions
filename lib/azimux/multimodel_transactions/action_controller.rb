module Azimux
  module MultimodelTransactions
    module ActionController
      protected
      def ax_multimodel_transaction objects, options = {}, &block
        reraise = options[:reraise]

        begin
          already_in = options[:already_in]
          connections = []

          if already_in
            already_in = [already_in] unless already_in.is_a? Array

            already_in.each do |object|
              connection = object
              if object.is_a? ActiveRecord::Base
                connection = object.connection
              elsif object.is_a?(Class) && object.ancestors.include?(ActiveRecord::Base)
                connection = object.connection
              end

              connections << connection unless connections.include? connection
            end
          end

          objects = objects.map do |object|
            if object.is_a?(Class)
              object
            else
              object.class
            end
          end

          objects.reverse.inject(block) do |proc_object, klass|
            if connections.include? klass.connection
              proc_object
            else
              connections << klass.connection

              proc do
                klass.transaction do
                  proc_object.call
                end
              end
            end
          end.call

        rescue Azimux::MultimodelTransactions::Rollback
          raise if reraise
          raise ActiveRecord::Rollback if already_in
        end
      end

      def ax_multimodel_if(models, options = {})
        if_proc = options[:if]
        is_true = options[:is_true]
        is_false = options[:is_false]
        retval = nil

        if models.blank?
          raise "ax_multimodel_if must be called with options[:models] set to an array of the models involved"
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
          models.reverse.inject(bool_proc) do |proc_object, model|
            proc do
              model.rollback_active_record_state! do
                proc_object.call
              end
            end
          end.call
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