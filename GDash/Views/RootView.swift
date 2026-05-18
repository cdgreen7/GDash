//
//  RootView.swift
//  GDash
//
//  Created by Caden Greenhalgh on 5/17/26.
//

import SwiftUI

struct RootView: View {

    @State private var loggedIn = false

    var body: some View {

        if loggedIn {
            MainTabView()
        } else {
            LoginView(loggedIn: $loggedIn)
        }
    }
}

struct LoginView: View {

    @Binding var loggedIn: Bool

    var body: some View {

        VStack(spacing: 20) {

            Text("GDash")

                .font(.largeTitle)

            Button("Login") {

                loggedIn = true

            }

        }

    }

}

struct MainTabView: View {

    var body: some View {

        TabView {

            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack {
                AssignmentsView()
            }
            .tabItem {
                Label("Assignments", systemImage: "checklist")
            }

            NavigationStack {
                CalendarView()
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }

            NavigationStack {
                FinancesView()
            }
            .tabItem {
                Label("Finances", systemImage: "dollarsign.circle")
            }

            NavigationStack {
                HabitsView()
            }
            .tabItem {
                Label("Habits", systemImage: "heart")
            }
        }
    }
}
