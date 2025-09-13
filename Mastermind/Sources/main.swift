import Foundation

//GameErrors

enum GameError: Error {
    case networkError
    case invalidResponse
    case serverError
    case gameNotFound
    case invalidGuess
    case apiError(String)
    case jsonDecodingError
}

extension GameError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection failed"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError:
            return "Server error occurred"
        case .gameNotFound:
            return "Game not found"
        case .invalidGuess:
            return "Invalid guess format"
        case .apiError(let message):
            return message
        case .jsonDecodingError:
            return "Invalid response data from server"
        }
    }
}


//MastermindAPI

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

class MastermindAPI {
    private let baseURL = "https://mastermind.darkube.app"
    
    func createGame() async throws -> String {
        guard let url = URL(string: "\(baseURL)/game") else {
            throw GameError.networkError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GameError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200:
                do {
                    let gameResponse = try JSONDecoder().decode(CreateGameResponse.self, from: data)
                    return gameResponse.game_id
                } catch {
                    throw GameError.jsonDecodingError
                }
            case 500:
                let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                throw GameError.apiError(errorResponse?.error ?? "Server error")
            default:
                throw GameError.serverError
            }
        } catch let error as GameError {
            throw error
        } catch {
            throw GameError.networkError
        }
    }
    
    func submitGuess(gameID: String, guess: String) async throws -> GuessResponse {
        guard let url = URL(string: "\(baseURL)/guess") else {
            throw GameError.networkError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let guessRequest = GuessRequest(game_id: gameID, guess: guess)
        request.httpBody = try JSONEncoder().encode(guessRequest)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GameError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200:
                do {
                    return try JSONDecoder().decode(GuessResponse.self, from: data)
                } catch {
                    throw GameError.jsonDecodingError
                }
            case 400:
                let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                throw GameError.apiError(errorResponse?.error ?? "Invalid guess")
            case 404:
                let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                throw GameError.apiError(errorResponse?.error ?? "Game not found")
            case 500:
                let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                throw GameError.apiError(errorResponse?.error ?? "Server error")
            default:
                throw GameError.serverError
            }
        } catch let error as GameError {
            throw error
        } catch {
            throw GameError.networkError
        }
    }
    
    func deleteGame(gameID: String) async throws {
        guard let url = URL(string: "\(baseURL)/game/\(gameID)") else {
            throw GameError.networkError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GameError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 204:
                // Success - no content
                return
            case 404:
                throw GameError.gameNotFound
            case 500:
                let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                throw GameError.apiError(errorResponse?.error ?? "Server error")
            default:
                throw GameError.serverError
            }
        } catch let error as GameError {
            throw error
        } catch {
            throw GameError.networkError
        }
    }
}


//Models

struct CreateGameResponse: Codable {
    let game_id: String
}

struct ErrorResponse: Codable {
    let error: String
}

struct GuessRequest: Codable {
    let game_id: String
    let guess: String
}

struct GuessResponse: Codable {
    let black: Int
    let white: Int
}


//MasterMindGame

class MastermindGame {
    private let api = MastermindAPI()
    private var gameID: String?
    
    func start() async {
        printWelcomeMessage()
        
        do {
            gameID = try await api.createGame()
            await playGame()
        } catch {
            handleStartGameError(error)
        }
    }
    
    private func printWelcomeMessage() {
        print("Welcome to Mastermind!")
        print("Guess the 4-digit code (digits 1-6).")
        print("B = correct digit in correct position")
        print("W = correct digit in wrong position")
        print("Type 'exit' to quit.\n")
    }
    
    private func handleStartGameError(_ error: Error) {
        switch error {
        case GameError.networkError:
            print("Network Error:check your internet connection and try again")
        case GameError.serverError:
            print("Server Error:try again later")
        case GameError.jsonDecodingError:
            print("Invalid response Error:try again later")
        case let GameError.apiError(message):
            print("Error: \(message)")
        default:
            print("Error: Could not start game")
            print("try again")
        }
    }
    
    private func playGame() async {
        var attemptCount = 0
        
        while true {
            attemptCount += 1
            print("Attempt \(attemptCount)")
            print("New game started. Enter your guess:", terminator: "")
            
            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                print(" Please enter a valid input")
                continue
            }
            
            if input.lowercased() == "exit" {
                await handleExit()
            }
            
            if isValidGuess(input) {
                await processGuess(input)
            } else {
                print("Each digit must be between 1 and 6")
                attemptCount -= 1 // Don't count invalid attempts
            }
        }
    }
    
    private func handleExit() async -> Never {
        if let gameID = gameID {
            try? await api.deleteGame(gameID: gameID)
        }
        print("Goodbye!")
        exit(0)
    }
    
    private func processGuess(_ guess: String) async {
        guard let gameID = gameID else { return }
        
        do {
            let response = try await api.submitGuess(gameID: gameID, guess: guess)
            let result = String(repeating: "B", count: response.black) + String(repeating: "W", count: response.white)
            
            if response.black == 4 {
                await handleWin(guess)
            } else {
                print("Result: \(result.isEmpty ? "None" : result)")
            }
        } catch {
            handleGuessError(error)
        }
    }
    
    private func handleWin(_ guess: String) async {
        print("Congratulations! You guessed the code!")
        print("🏆 The secret code was \(guess)")
        try? await api.deleteGame(gameID: gameID!)
        
        await askForNewGame()
    }
    
    private func askForNewGame() async {
        print("\n Do you want to play again? (y/n): ", terminator: "")
        
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            print("Invalid input. Type 'exit' to quit.")
            await askForNewGame()
            return
        }
        
        if input == "y" || input == "yes" {
            print("\n" + String(repeating: "=", count: 50))
            await start()
        } else if input == "n" || input == "no" || input == "exit" {
            print("Goodbye!")
            exit(0)
        } else {
            print("Please enter 'y' for yes, 'n' for no, or 'exit' to quit.")
            await askForNewGame()
        }
    }
    
    private func handleGuessError(_ error: Error) {
        switch error {
        case GameError.invalidGuess:
            print("Error: Invalid guess format")
        case GameError.gameNotFound:
            print("Error: Game not found")
        case GameError.networkError:
            print("Network Error:check your internet connection and try again")
        case GameError.jsonDecodingError:
            print("Invalid response Error:try again later")
        case let GameError.apiError(message):
            print("Error: \(message)")
        default:
            print("Error: Could not process guess")
            print("Please try again")
        }
    }
    
    private func isValidGuess(_ guess: String) -> Bool {
        guard guess.count == 4 else { return false }
        return guess.allSatisfy { char in
            guard let digit = Int(String(char)) else { return false }
            return digit >= 1 && digit <= 6
        }
    }
}


Task {
    let game = MastermindGame()
    await game.start()
}

RunLoop.main.run()
