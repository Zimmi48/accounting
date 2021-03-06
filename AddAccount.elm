module AddAccount exposing (Model, init, Msg, update, view)


import Html exposing (..)
import Html.Attributes exposing (..)
import Json.Encode as Json
import Lib exposing (..)
import Maybe.Extra as Maybe
import String


-- TODO : enforce only one account with the same name


type alias Model =
  { name : String
  , initialValue : Maybe Float
  }


init : Model
init = Model "" (Just 0)


type Msg
  = UpdateName String
  | UpdateValue String
  | Submit


update : Msg -> Model -> (Model, Maybe Json.Value)
update msg model =
  case msg of
    UpdateName s ->
      ( { model |
          name = String.left 50 s
        }
      , Nothing
      )

    UpdateValue s ->
      ( { model |
          initialValue = Result.toMaybe <| String.toFloat s
        }
      , Nothing
      )

    Submit ->
      case model.initialValue of
        Just value ->
          if String.isEmpty model.name then
            (model, Nothing)
          else
            ( model
            , Json.object
                [ ("name", Json.string model.name)
                , ("value", Json.float value)
                ] |> Just
            )

        Nothing ->
          (model, Nothing)


view : Model -> Html Msg
view model =
  viewForm
    (String.isEmpty model.name || Maybe.isNothing model.initialValue)
    Submit
    "Create account"
    [ inputGr "accountname" "Name" UpdateName
        [ placeholder "Current account"
        , value model.name
        , required True
        ]
    , inputGr "value" "Initial value" UpdateValue
        [ value
          <| Maybe.withDefault ""
          <| Maybe.map toString model.initialValue
        , type' "number"
        , step "0.01"
        , required True
        ]
    ]


