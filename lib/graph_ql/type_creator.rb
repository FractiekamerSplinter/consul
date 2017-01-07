module GraphQL
  class TypeCreator
    SCALAR_TYPES = {
      integer: GraphQL::INT_TYPE,
      boolean: GraphQL::BOOLEAN_TYPE,
      float: GraphQL::FLOAT_TYPE,
      double: GraphQL::FLOAT_TYPE,
      string: GraphQL::STRING_TYPE
    }

    attr_accessor :created_types, :api_type_definitions

    def initialize(api_type_definitions)
      @api_type_definitions = api_type_definitions
      @created_types = {}
    end

    def create_api_types
      api_type_definitions.each do |model, info|
        self.create_type(model, info[:fields])
      end
    end

    def create_type(model, fields)
      type_creator = self

      created_type = GraphQL::ObjectType.define do

        name(model.name)
        description("#{model.model_name.human}")

        # Make a field for each column, association or method
        fields.each do |field_name, field_type|
          case TypeCreator.type_kind(field_type)
          when :scalar
            field(field_name, SCALAR_TYPES[field_type])
          when :simple_association
            field(field_name, -> { type_creator.created_types[field_type] }) do
              resolve GraphQL::AssociationResolver.new(field_name, field_type)
            end
          when :paginated_association
            field_type = field_type.first
            connection(field_name, -> { type_creator.created_types[field_type].connection_type }) do
              resolve GraphQL::AssociationResolver.new(field_name, field_type)
            end
          end
        end

      end
      created_types[model] = created_type
      return created_type # GraphQL::ObjectType
    end

    def create_query_root
      type_creator = self

      GraphQL::ObjectType.define do
        name 'QueryRoot'
        description 'The query root for this schema'

        type_creator.created_types.each do |model, created_type|

          # create an entry field to retrive a single object
          if type_creator.api_type_definitions[model][:fields][:id]
            field model.name.underscore.to_sym do
              type created_type
              description "Find one #{model.model_name.human} by ID"
              argument :id, !types.ID
              resolve GraphQL::RootElementResolver.new(model)
            end
          end

          # create an entry filed to retrive a paginated collection
          connection model.name.underscore.pluralize.to_sym, created_type.connection_type do
            description "Find all #{model.model_name.human.pluralize}"
            resolve GraphQL::RootCollectionResolver.new(model)
          end

        end
      end
    end

    def self.type_kind(type)
      if SCALAR_TYPES[type]
        :scalar
      elsif type.class == Class
        :simple_association
      elsif type.class == Array
        :paginated_association
      end
    end

  end
end
