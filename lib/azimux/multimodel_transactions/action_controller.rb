module Azimux
  module MultimodelTransactions
    module ActionController
      protected
      def ax_multimodel_transaction objects, options = {}, &block
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
      end

      def ax_multimodel_if(models, options = {})
        if_proc = options[:if]
        is_true = options[:is_true]
        is_false = options[:is_false]
        reraise = options[:reraise]
        retval = nil

        rollback_transaction = if options.keys.include? :rollback_transaction
          options[:rollback_transaction]
        else
          true
        end

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
            raise Azimux::MultimodelTransactions::UncheckedRollbackException
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
        rescue Azimux::MultimodelTransactions::UncheckedRollbackException
          retval = if is_false
            is_false.call
          else
            false
          end

          if rollback_transaction
            models.map(&:class).map(&:connection).uniq.map(&:rollback_db_transaction)
          end

          raise if reraise
        end

        retval
      end

    end

  end
end

class Azimux::MultimodelTransactions::UncheckedRollbackException < Exception
end