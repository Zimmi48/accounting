module Kinvey exposing
  ( Error(..)
  , errorToString
  , Auth
  , Session
  , signup
  , login
  , getUserData
  , setUserData
  , createData
  , getData
  )


import Base64
import Http exposing (Error(..))
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (encode)
import Result
import Task exposing (Task, andThen, toResult)


apiVersion = ("X-Kinvey-Api-Version" , "3")


contentType = ("Content-Type", "application/json")


type Error
  = AuthError String
  | HttpError Http.Error


errorToString : Error -> String
errorToString e =
  case e of
    AuthError s ->
      "Authentication error: " ++ s

    HttpError Timeout ->
      "Timeout"

    HttpError NetworkError ->
      "Network error"

    HttpError (UnexpectedPayload s) ->
      "Unexpected payload: " ++ s

    HttpError (BadResponse _ s) ->
      "Bad response: " ++ s


type alias Auth =
  { appId : String
  , appSecret : String
  }


type alias Session =
  { token : String
  , id : String
  }


getAuthToken : Auth -> Task Error String
getAuthToken { appId , appSecret } =
  appId ++ ":" ++ appSecret
  |> Base64.encode
  |> Result.map ((++) "Basic ")
  |> Result.formatError AuthError
  |> Task.fromResult


baseUserUrl : Auth -> String
baseUserUrl { appId } = "https://baas.kinvey.com/user/" ++ appId ++ "/"


baseDataUrl : Auth -> String
baseDataUrl { appId } = "https://baas.kinvey.com/appdata/" ++ appId ++ "/"


{-| signup creates a new user given auth information, an email and a password -}
signup : Auth -> String -> String -> List (String, Encode.Value) -> Task Error ()
signup auth username password fields =
  getAuthToken auth `andThen` \token ->
  Http.send
    Http.defaultSettings
    { verb = "POST"
    , headers =
        [ ("Authorization" , token)
        , contentType
        , apiVersion
        ]
        , url = baseUserUrl auth
        , body =
            Http.string
            <| encode 0
            <| Encode.object
            <|  [ ("username" , Encode.string username)
                , ("password" , Encode.string password)
                ] ++
                List.filter
                  (\(field, _) -> not <| field == "username" || field == "password")
                  fields
    }
  |> Http.fromJson (Decode.succeed ())
  |> Task.mapError HttpError


{-| login starts a session given auth information, an email and a password -}
login : Auth -> String -> String -> Decoder a -> Task Error (Session , a)
login auth email password decoder =
  getAuthToken auth `andThen` \token ->
  Http.send
    Http.defaultSettings
    { verb = "POST"
    , headers =
        [ ("Authorization" , token)
        , contentType
        , apiVersion
        ]
        , url = baseUserUrl auth ++ "login"
        , body =
            Http.string
            <| Encode.encode 0
            <| Encode.object
                [ ("username" , Encode.string email)
                , ("password" , Encode.string password)
                ]
    }
  |> Http.fromJson
      ( Decode.at ["_kmd" , "authtoken"] Decode.string
                `Decode.andThen` \token ->
        Decode.at ["_id"] Decode.string
                `Decode.andThen` \id ->
        Decode.map ((,) {token = "Kinvey " ++ token , id = id}) decoder
      )
  |> Task.mapError HttpError


{-| getUserData retrieves the requested properties given a session token -}
getUserData : Auth -> Session -> Decoder a -> Task Error a
getUserData auth session decoder =
  Http.send
    Http.defaultSettings
    { verb = "GET"
    , headers =
        [ ("Authorization" , session.token)
        , apiVersion
        ]
        , url = baseUserUrl auth ++ "_me"
        , body = Http.empty
    }
  |> Http.fromJson decoder
  |> Task.mapError HttpError


{-| setUserData adds or updates the listed fields given a session token -}
setUserData : Auth -> Session -> List (String, Encode.Value) -> Task Error ()
setUserData auth session fields =
  Http.send
    Http.defaultSettings
    { verb = "PUT"
    , headers =
        [ ("Authorization" , session.token)
        , contentType
        , apiVersion
        ]
    , url = baseUserUrl auth ++ session.id
    , body =
        Http.string
        <| encode 0
        <| Encode.object fields
    }
  |> Http.fromJson (Decode.succeed ())
  |> Task.mapError HttpError


createData : Auth -> Session -> String -> Encode.Value -> Task Error ()
createData auth session collection data =
  Http.send
    Http.defaultSettings
    { verb = "POST"
    , headers =
        [ ("Authorization" , session.token)
        , contentType
        , apiVersion
        ]
    , url = baseDataUrl auth ++ collection
    , body = Http.string <| encode 0 data
    }
  |> Http.fromJson (Decode.succeed ())
  |> Task.mapError HttpError


getData : Auth -> Session -> String -> Decoder a -> Task Error (List a)
getData auth session collection decoder =
  Http.send
    Http.defaultSettings
    { verb = "GET"
    , headers =
        [ ("Authorization" , session.token)
        , apiVersion
        ]
    , url = baseDataUrl auth ++ collection
    , body = Http.empty
    }
  |> Http.fromJson (Decode.list decoder)
  |> Task.mapError HttpError





