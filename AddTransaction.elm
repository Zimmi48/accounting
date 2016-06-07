module AddTransaction exposing (Model, init, Msg, update, view)


import Date exposing (Date)
import Date.Format as Date
import DatePicker exposing (DatePicker, defaultSettings)
import Html exposing (..)
import Html.App as App
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Maybe
import Maybe.Extra as Maybe
import Positive exposing (Positive)
import String


main : Program Never
main =
  App.program
    { init = init
    , update =
        (\msg model ->
           let (model, cmd, _) = update msg model in
           (model, cmd)
        )
    , view = view
    , subscriptions = (\_ -> Sub.none)
    }


type alias Model =
  { object : String
  , value : Maybe (Positive Float)
  , valueString : String
  , datePicker : DatePicker
  , date : Maybe Date
  }


init : (Model, Cmd Msg)
init =
  let
    (dateModel, dateCmd) =
      DatePicker.init
        { defaultSettings |
          placeholder = "1 Jan 1970"
        , dateFormatter = Date.format "%e %b %Y"
        , firstDayOfWeek = Date.Mon
        , inputClassList = [ ("form-control", True) ]
        , inputName = Just "date"
        }

  in
    { object = ""
    , value = Nothing
    , valueString = ""
    , datePicker = dateModel
    , date = Nothing
    }
  ! [ Cmd.map UpdateDate dateCmd
    ]


type Msg
  = UpdateObject String
  | UpdateValue String
  | UpdateDate DatePicker.Msg
  | Submit


update : Msg -> Model -> (Model, Cmd Msg, Maybe (String, Positive Float, Date))
update msg model =
  case msg of
    UpdateObject string ->
      ( { model |
          object = String.left 50 string
        }
      , Cmd.none
      , Nothing
      )

    UpdateValue string ->
      ( { model |
          value =
            (String.toFloat string |> Result.toMaybe)
            `Maybe.andThen` Positive.fromNum
        , valueString = string
        }
      , Cmd.none
      , Nothing
      )

    UpdateDate msg ->
      let
        (dateModel, dateCmd, date) =
          DatePicker.update msg model.datePicker
      in
      ( { model |
          datePicker = dateModel
        , date = Maybe.oneOf [date, model.date]
        }
      , Cmd.map UpdateDate dateCmd
      , Nothing
      )

    Submit ->
      case (model.value , model.date) of
        (Just value, Just date) ->
          if String.isEmpty model.object then
            (model, Cmd.none, Nothing)

          else
            ( model
            , Cmd.none
            , Just (model.object, value, date)
            )

        _ ->
          (model, Cmd.none, Nothing)


view : Model -> Html Msg
view model =
  let
    notready =
      String.isEmpty model.object
      || Maybe.isNothing model.value
      || Maybe.isNothing model.date
  in

  Html.form
    [ onSubmit Submit ]
    [ div
        [ class "form-group" ]
        [ label [ for "object" ] [ text "Object" ]
        , input
            [ placeholder "Groceries"
            , value model.object
            , name "object"
            , onInput UpdateObject
            , class "form-control"
            ] []
        ]
    , div
        [ class "form-group" ]
        [ label [ for "value" ] [ text "Value" ]
        , input
            [ placeholder "23.33"
            , value model.valueString
            , type' "number"
            , name "value"
            , Html.Attributes.min "0.01"
            , step "0.01"
            , required True
            , onInput UpdateValue
            , class "form-control"
            ] []
        ]
    , div
        [ class "form-group" ]
        [ label [ for "date" ] [ text "Date" ]
        , App.map UpdateDate <| DatePicker.view model.datePicker
        ]
    , input
        [ type' "submit"
        , disabled notready
        , classList
            [ ("btn", True)
            , ("btn-success", True)
            ]
        ] []
    ]




